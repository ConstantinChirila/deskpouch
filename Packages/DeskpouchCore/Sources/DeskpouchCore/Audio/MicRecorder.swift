import AVFoundation
import Synchronization

public enum MicRecorderError: Error, Sendable {
    case noInputDevice
    case unsupportedFormat
}

/// Captures a microphone (system default or `deviceUID`) into 16 kHz mono Float32 samples and tracks a live level for meters.
@MainActor
public final class MicRecorder {
    public static let sampleRate: Double = 16_000

    private let engine = AVAudioEngine()
    private let store = SampleStore()
    public private(set) var isRecording = false

    /// Core Audio UID of the microphone to use. nil follows the system default input.
    public var deviceUID: String?

    public init() {}

    /// Level of the most recent input buffer, 0...1. Safe to read from a timer while recording.
    public var currentLevel: Float { store.level }

    public func start() throws {
        guard !isRecording else { return }
        let input = engine.inputNode
        if let deviceUID, let device = AudioInputDevices.device(uid: deviceUID), let unit = input.audioUnit {
            var deviceID = device.id
            let status = AudioUnitSetProperty(
                unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                &deviceID, UInt32(MemoryLayout<AudioDeviceID>.size)
            )
            if status != noErr { throw MicRecorderError.noInputDevice }
        }
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else { throw MicRecorderError.noInputDevice }
        guard let target = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: Self.sampleRate, channels: 1, interleaved: false
        ), let converter = AVAudioConverter(from: inputFormat, to: target) else {
            throw MicRecorderError.unsupportedFormat
        }
        store.reset()
        Self.installTap(on: input, format: inputFormat, box: ConverterBox(converter: converter, target: target), store: store)
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw error
        }
        isRecording = true
    }

    /// The tap block runs on AVFoundation's realtime queue. Installing it from a nonisolated context keeps the
    /// closure free of main-actor isolation, which the runtime would otherwise assert on that queue.
    private nonisolated static func installTap(
        on input: AVAudioInputNode, format: AVAudioFormat, box: ConverterBox, store: SampleStore
    ) {
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { buffer, _ in
            box.ingest(buffer, into: store)
        }
    }

    /// Stops capture and returns everything recorded since `start()`.
    @discardableResult
    public func stop() -> [Float] {
        guard isRecording else { return [] }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRecording = false
        return store.drain()
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

/// Owns the converter. Only ever touched from the input tap's thread.
private final class ConverterBox: @unchecked Sendable {
    let converter: AVAudioConverter
    let target: AVAudioFormat

    init(converter: AVAudioConverter, target: AVAudioFormat) {
        self.converter = converter
        self.target = target
    }

    func ingest(_ buffer: AVAudioPCMBuffer, into store: SampleStore) {
        let level: Float
        if let channel = buffer.floatChannelData?[0] {
            level = LevelMath.normalized(rms: LevelMath.rms(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength))))
        } else {
            level = 0
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
