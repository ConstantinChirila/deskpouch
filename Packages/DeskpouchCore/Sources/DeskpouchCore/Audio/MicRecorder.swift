import AVFoundation
import os
import Synchronization

public enum MicRecorderError: Error, Sendable {
    case noInputDevice
    case unsupportedFormat
}

private let log = Logger(subsystem: "com.constantinchirila.deskpouch", category: "mic")

/// Captures a microphone (system default or `deviceUID`) into 16 kHz mono Float32 samples and tracks a live level for meters.
@MainActor
public final class MicRecorder {
    public nonisolated static let sampleRate: Double = 16_000

    /// A fresh engine per recording: a reused one keeps the device it was last pinned to and its old formats.
    private var engine: AVAudioEngine?
    private var configurationObserver: (any NSObjectProtocol)?
    private let store = SampleStore()
    public private(set) var isRecording = false

    /// Core Audio UID of the microphone to use. nil follows the system default input.
    public var deviceUID: String?

    /// The hardware changed under a recording (the microphone was unplugged, its format changed) and capture
    /// stopped. `stop()` still returns what was captured until then.
    public var onInterrupted: (@MainActor () -> Void)?

    public init() {}

    /// Level of the most recent input buffer, 0...1. Safe to read from a timer while recording.
    public var currentLevel: Float { store.level }

    public func start() throws {
        guard !isRecording else { return }
        let engine = AVAudioEngine()
        let input = engine.inputNode
        if let deviceUID {
            if let device = AudioInputDevices.device(uid: deviceUID), let unit = input.audioUnit {
                var deviceID = device.id
                let status = AudioUnitSetProperty(
                    unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                    &deviceID, UInt32(MemoryLayout<AudioDeviceID>.size)
                )
                if status != noErr { throw MicRecorderError.noInputDevice }
            } else {
                log.info("microphone \(deviceUID, privacy: .public) is gone, using the system default")
            }
        }
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else { throw MicRecorderError.noInputDevice }
        guard let target = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: Self.sampleRate, channels: 1, interleaved: false
        ) else {
            throw MicRecorderError.unsupportedFormat
        }
        store.reset()
        Self.installTap(on: input, box: ConverterBox(target: target), store: store)
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw error
        }
        self.engine = engine
        isRecording = true
        let id = ObjectIdentifier(engine)
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.configurationChanged(engine: id) }
        }
    }

    /// The tap block runs on AVFoundation's realtime queue. Installing it from a nonisolated context keeps the
    /// closure free of main-actor isolation, which the runtime would otherwise assert on that queue.
    /// The tap takes the bus's own format (nil): a format read just after a device switch can be stale, and a
    /// mismatch raises an Objective-C exception. The converter is built from the first buffer instead.
    private nonisolated static func installTap(on input: AVAudioInputNode, box: ConverterBox, store: SampleStore) {
        input.installTap(onBus: 0, bufferSize: 2048, format: nil) { buffer, _ in
            box.ingest(buffer, into: store)
        }
    }

    /// Stops capture and returns everything recorded since `start()`.
    @discardableResult
    public func stop() -> [Float] {
        tearDown()
        return store.drain()
    }

    private func tearDown() {
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
        configurationObserver = nil
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        isRecording = false
    }

    /// The engine stops itself before it posts the change. One that is still running is the echo of the device
    /// switch in `start()`.
    private func configurationChanged(engine id: ObjectIdentifier) {
        guard isRecording, let engine, ObjectIdentifier(engine) == id, !engine.isRunning else { return }
        log.info("audio configuration changed while recording, stopping")
        tearDown()
        onInterrupted?()
    }
}

/// Samples and level shared between the audio thread and the main actor.
final class SampleStore: Sendable {
    private struct State {
        var samples: [Float] = []
        var level: Float = 0
    }

    private let state = Mutex(State())

    var level: Float { state.withLock { $0.level } }

    func reset() { state.withLock { $0 = State() } }

    func append(_ samples: [Float], level: Float) {
        state.withLock {
            $0.samples.append(contentsOf: samples)
            $0.level = level
        }
    }

    func drain() -> [Float] {
        state.withLock {
            let out = $0.samples
            $0 = State()
            return out
        }
    }
}

/// Owns the converter, built from the format of the buffers the tap delivers. Only ever touched from the
/// input tap's thread.
private final class ConverterBox: @unchecked Sendable {
    private var converter: AVAudioConverter?
    let target: AVAudioFormat

    init(target: AVAudioFormat) {
        self.target = target
    }

    private func converter(for format: AVAudioFormat) -> AVAudioConverter? {
        if let converter, converter.inputFormat == format { return converter }
        converter = AVAudioConverter(from: format, to: target)
        return converter
    }

    func ingest(_ buffer: AVAudioPCMBuffer, into store: SampleStore) {
        let level: Float
        if let channel = buffer.floatChannelData?[0] {
            level = LevelMath.normalized(rms: LevelMath.rms(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength))))
        } else {
            level = 0
        }

        guard let converter = converter(for: buffer.format) else {
            store.append([], level: level)
            return
        }
        let ratio = target.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 32
        guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }

        // The converter pulls input through a @Sendable block; hand it this one buffer exactly once.
        let feed = OneShotFeed(buffer)
        var error: NSError?
        let status = converter.convert(to: out, error: &error) { _, outStatus in
            if let next = feed.take() {
                outStatus.pointee = .haveData
                return next
            }
            outStatus.pointee = .noDataNow
            return nil
        }
        guard status != .error, let data = out.floatChannelData?[0] else {
            store.append([], level: level)
            return
        }
        store.append(Array(UnsafeBufferPointer(start: data, count: Int(out.frameLength))), level: level)
    }
}

/// Hands a buffer to the converter's input block once. Only used within a single `convert` call.
private final class OneShotFeed: @unchecked Sendable {
    private var buffer: AVAudioPCMBuffer?
    init(_ buffer: AVAudioPCMBuffer) { self.buffer = buffer }
    func take() -> AVAudioPCMBuffer? {
        defer { buffer = nil }
        return buffer
    }
}
