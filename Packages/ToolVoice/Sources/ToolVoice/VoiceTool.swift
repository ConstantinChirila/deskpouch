import DeskpouchCore
import Foundation
import os

private let log = Logger(subsystem: "com.constantinchirila.deskpouch", category: "voice")

/// Hold-to-talk dictation. Hold the key, speak, release: the transcript is emitted as a `ToolResult`.
@MainActor
public final class VoiceTool: Tool {
    public let id = "voice"
    public let name = "Voice"
    /// Persisted under `voice.holdKey`. The shell re-registers the hotkey when it changes this.
    public var holdKey: ModifierKey? {
        didSet { UserDefaults.standard.set(holdKey.map { Int($0.rawValue) }, forKey: Self.holdKeyDefaultsKey) }
    }
    public let defaultOutput = ToolOutputConfig(actions: [.paste, .copy, .history])

    /// Engine status for the panel, e.g. "Parakeet v3 · local" or "Downloading model · 42%".
    public var onStatus: (@MainActor (String) -> Void)?

    /// Holds shorter than this are treated as accidental taps.
    static let minimumHold: TimeInterval = 0.4

    static let languageDefaultsKey = "voice.language"
    static let holdKeyDefaultsKey = "voice.holdKey"
    static let microphoneDefaultsKey = "voice.microphone"

    /// Core Audio UID of the microphone, nil for the system default. Persisted.
    public var microphoneUID: String? {
        get { recorder.deviceUID }
        set {
            recorder.deviceUID = newValue
            UserDefaults.standard.set(newValue, forKey: Self.microphoneDefaultsKey)
        }
    }

    /// Display name for the engine popup.
    public var engineName: String { transcriber.displayName }

    /// "623 MB · downloaded" or "not downloaded", from the FluidAudio model folder.
    public var modelStatus: String {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let folder = support.appending(path: "FluidAudio", directoryHint: .isDirectory)
        guard let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.fileSizeKey]) else {
            return "not downloaded"
        }
        var bytes: Int64 = 0
        for case let url as URL in files {
            bytes += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        guard bytes > 0 else { return "not downloaded" }
        return "\(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)) · downloaded"
    }

    /// Localised name for a supported language code.
    public static func languageName(_ code: String) -> String {
        Locale.current.localizedString(forLanguageCode: code)?.capitalized ?? code.uppercased()
    }

    /// ISO 639-1 language hint for the engine. Persisted. Defaults to the system language when supported, else English.
    public var language: String {
        get {
            if let stored = UserDefaults.standard.string(forKey: Self.languageDefaultsKey),
               transcriber.supportedLanguages.contains(stored) {
                return stored
            }
            let system = Locale.current.language.languageCode?.identifier ?? "en"
            return transcriber.supportedLanguages.contains(system) ? system : "en"
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.languageDefaultsKey)
            onStatus?(statusLine)
        }
    }

    public var supportedLanguages: [String] { transcriber.supportedLanguages }

    /// "Parakeet v3 · EN" style line for the panel.
    private var statusLine: String { "\(transcriber.displayName) · \(language.uppercased())" }

    private let transcriber: any Transcriber
    private let recorder = MicRecorder()
    private var context: ToolContext?
    private var job: Task<Void, Never>?

    public init(transcriber: any Transcriber = ParakeetTranscriber()) {
        self.transcriber = transcriber
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Self.holdKeyDefaultsKey) != nil,
           let key = ModifierKey(rawValue: UInt16(clamping: defaults.integer(forKey: Self.holdKeyDefaultsKey))) {
            holdKey = key
        } else {
            holdKey = .rightOption
        }
        recorder.deviceUID = defaults.string(forKey: Self.microphoneDefaultsKey)
    }

    public func attach(_ context: ToolContext) {
        self.context = context
    }

    /// Downloads and loads the model in the background so the first dictation is not stuck waiting.
    public func warmUp() {
        onStatus?("\(transcriber.displayName) · loading")
        Task { [transcriber, self] in
            do {
                try await transcriber.prepare { message in
                    Task { @MainActor in self.onStatus?(message) }
                }
                self.onStatus?(self.statusLine)
            } catch {
                self.onStatus?("\(transcriber.displayName) · failed to load")
            }
        }
    }

    public func holdBegan() {
        guard let context else { return }
        job?.cancel()
        job = nil
        switch Permissions.microphone {
        case .undetermined:
            // First use: ask, and let this hold go. The next one records.
            log.info("microphone permission undetermined, prompting")
            context.overlay.flash(.preparing("Allow microphone access, then hold again"), for: .seconds(3))
            Task { [weak self] in
                let granted = await Permissions.requestMicrophone()
                log.info("microphone permission granted=\(granted)")
                self?.context?.overlay.hide()
            }
            return
        case .denied:
            log.info("microphone permission denied")
            context.overlay.flash(.failed("Microphone access is off for Deskpouch"), for: .seconds(2))
            Permissions.openMicrophoneSettings()
            return
        case .granted:
            break
        }
        do {
            try recorder.start()
        } catch {
            log.error("recorder start failed: \(String(describing: error), privacy: .public)")
            context.overlay.flash(.failed("Microphone unavailable"), for: .seconds(2))
            return
        }
        log.info("recording started")
        let recorder = recorder
        context.overlay.showListening { recorder.currentLevel }
    }

    public func holdEnded() {
        guard let context, recorder.isRecording else { return }
        let samples = recorder.stop()
        let duration = Double(samples.count) / MicRecorder.sampleRate
        log.info("recording stopped: \(samples.count) samples, \(duration, format: .fixed(precision: 2))s")
        guard duration >= Self.minimumHold else {
            context.overlay.hide()
            return
        }
        job = Task { [weak self] in
            await self?.transcribe(samples, duration: duration, emit: true)
        }
    }

    /// Runs the full transcription path on given samples but never emits a result (so nothing is pasted).
    /// Returns the transcript. Used by the demo mode to check the engine without a microphone.
    public func debugTranscribe(_ samples: [Float]) async -> String? {
        await transcribe(samples, duration: Double(samples.count) / MicRecorder.sampleRate, emit: false)
    }

    @discardableResult
    private func transcribe(_ samples: [Float], duration: TimeInterval, emit: Bool) async -> String? {
        guard let context else { return nil }
        let engine = transcriber.displayName
        context.overlay.show(.transcribing(detail: engine))
        do {
            try await transcriber.prepare { message in
                Task { @MainActor in context.overlay.show(.preparing(message)) }
            }
            if Task.isCancelled { return nil }
            if case .preparing = context.overlay.state {
                context.overlay.show(.transcribing(detail: engine))
            }
            let transcript = try await transcriber.transcribe(samples: samples, language: language)
            if Task.isCancelled { return nil }
            guard !transcript.text.isEmpty else {
                context.overlay.flash(.failed("Nothing heard"))
                return nil
            }
            if emit {
                context.emit(ToolResult(toolID: id, text: transcript.text, duration: duration))
            }
            return transcript.text
        } catch {
            log.error("transcription failed: \(String(describing: error), privacy: .public)")
            context.overlay.flash(.failed("Transcription failed"), for: .seconds(2))
            return nil
        }
    }
}
