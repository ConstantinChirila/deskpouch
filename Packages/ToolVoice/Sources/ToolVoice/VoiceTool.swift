import AppKit
import DeskpouchCore
import Foundation
import Synchronization
import os

private let log = Logger(subsystem: "com.constantinchirila.deskpouch", category: "voice")

/// Which speech engine dictation runs on. Persisted under `voice.engine`.
public enum VoiceEngine: String, CaseIterable, Sendable {
    /// Parakeet TDT 0.6B v3 through FluidAudio: downloaded once, best accuracy.
    case parakeet
    /// macOS's own on-device recognition: nothing to download, less accurate.
    case apple

    public var name: String {
        switch self {
        case .parakeet: "Parakeet v3"
        case .apple: "Apple Speech"
        }
    }
}

enum VoiceToolError: LocalizedError {
    case transcriptionTimedOut

    var errorDescription: String? {
        switch self {
        case .transcriptionTimedOut: "Transcription took too long"
        }
    }
}

/// What Voice needs from a microphone. `MicRecorder` is the real one; tests drive the hold logic with a fake.
@MainActor
public protocol VoiceRecording: AnyObject {
    var deviceUID: String? { get set }
    var isRecording: Bool { get }
    var currentLevel: Float { get }
    /// Capture stopped by itself (the microphone went away). `stop()` still returns what was captured.
    var onInterrupted: (@MainActor () -> Void)? { get set }
    func start() throws
    @discardableResult func stop() -> [Float]
}

extension MicRecorder: VoiceRecording {}

/// Hold-to-talk dictation. Hold the key, speak, release: the transcript is emitted as a `ToolResult`.
@MainActor
public final class VoiceTool: Tool {
    public let id = "voice"
    public let name = "Voice"
    /// Persisted under `voice.holdKey`. The shell re-registers the hotkey when it changes this.
    public var holdKey: ModifierKey? {
        didSet { defaults.set(holdKey.map { Int($0.rawValue) }, forKey: Self.holdKeyDefaultsKey) }
    }
    public let defaultOutput = ToolOutputConfig(actions: [.paste, .copy, .history])

    /// Engine status for the panel, e.g. "Parakeet v3 · local" or "Downloading model · 42%".
    public var onStatus: (@MainActor (String) -> Void)?

    /// Holds shorter than this are treated as accidental taps.
    static let minimumHold: TimeInterval = 0.4

    static let languageDefaultsKey = "voice.language"
    static let holdKeyDefaultsKey = "voice.holdKey"
    static let microphoneDefaultsKey = "voice.microphone"
    static let engineDefaultsKey = "voice.engine"

    /// Persisted. Switching to Parakeet starts its download; switching away leaves the download in place.
    public var engine: VoiceEngine {
        didSet {
            guard engine != oldValue else { return }
            defaults.set(engine.rawValue, forKey: Self.engineDefaultsKey)
            if engine == .parakeet { warmUp() } else { onStatus?(statusLine) }
        }
    }

    /// Where FluidAudio keeps the Parakeet v3 files. Removing it frees the download; the next Parakeet use fetches it again.
    static let parakeetFolder: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appending(path: "FluidAudio/Models/parakeet-tdt-0.6b-v3", directoryHint: .isDirectory)
    }()

    public var parakeetDownloaded: Bool { parakeetBytes > 0 }

    private var parakeetBytes: Int64 {
        guard let files = FileManager.default.enumerator(at: Self.parakeetFolder, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var bytes: Int64 = 0
        for case let url as URL in files {
            bytes += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return bytes
    }

    /// Deletes the Parakeet download. Only sensible while Apple Speech is selected.
    public func removeParakeetDownload() throws {
        try FileManager.default.removeItem(at: Self.parakeetFolder)
        onStatus?(statusLine)
    }

    /// One line per engine for the Model popup: what it costs and where it stands.
    public func engineDetail(_ engine: VoiceEngine) -> String {
        switch engine {
        case .parakeet:
            let bytes = parakeetBytes
            return bytes > 0
                ? "\(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)) · downloaded"
                : "about 470 MB, downloads on first use"
        case .apple:
            return "built into macOS · on device"
        }
    }
    static let skipFillersDefaultsKey = "voice.skipFillers"

    /// Drop "um", "uh", "hmm" from transcripts. Persisted, on by default. Parakeet has no knob for this,
    /// so `FillerFilter` cleans the text after decode, with the list for the dictation's language.
    public var skipFillers: Bool {
        didSet { defaults.set(skipFillers, forKey: Self.skipFillersDefaultsKey) }
    }

    static let spokenPunctuationDefaultsKey = "voice.spokenPunctuation"
    static let sayToSendDefaultsKey = "voice.sayToSend"
    static let numbersAsDigitsDefaultsKey = "voice.numbersAsDigits"
    static let tapToLockDefaultsKey = "voice.tapToLock"
    static let dictionaryDefaultsKey = "voice.dictionary"

    /// "comma", "question mark", "new line" become the marks they name. English commands. Persisted, off by default.
    public var spokenPunctuation: Bool {
        didSet { defaults.set(spokenPunctuation, forKey: Self.spokenPunctuationDefaultsKey) }
    }

    /// Spelled-out numbers the engine left as words become digits ("$232.50", "3:30 PM"). Only while the language
    /// is English. Persisted, on by default.
    public var numbersAsDigits: Bool {
        didSet { defaults.set(numbersAsDigits, forKey: Self.numbersAsDigitsDefaultsKey) }
    }

    /// A dictation that ends in "send" is pasted without it, then Return is pressed. Persisted, off by default.
    public var sayToSend: Bool {
        didSet { defaults.set(sayToSend, forKey: Self.sayToSendDefaultsKey) }
    }

    /// A tap of the hold key (shorter than `minimumHold`) keeps recording hands-free; the next tap finishes.
    /// Holding works as before. Persisted, off by default.
    public var tapToLock: Bool {
        didSet { defaults.set(tapToLock, forKey: Self.tapToLockDefaultsKey) }
    }

    /// Words the engine gets wrong and what to write instead. Persisted as JSON.
    public var dictionary: [WordReplacement] {
        didSet {
            replacements = WordReplacements(dictionary)
            defaults.set(try? JSONEncoder().encode(dictionary), forKey: Self.dictionaryDefaultsKey)
        }
    }

    private var replacements: WordReplacements

    /// A recording, locked or held, ends by itself after this long: the samples are held in memory, and a key
    /// release can go missing.
    public static let defaultLockLimit: Duration = .seconds(600)
    private let lockLimit: Duration

    /// A transcript that is ready this long after the key was released is not pasted: the user has moved on,
    /// and it would land in whatever app is in front by then. It goes to the clipboard instead.
    static let staleAfter: TimeInterval = 20

    /// One recognition may run this long, plus the length of the recording, before it is given up on, so a hung
    /// engine cannot block the dictations queued behind it.
    public static let defaultTranscribeLimit: Duration = .seconds(60)
    private let transcribeLimit: Duration

    /// A recording ended without a key release (it reached its limit, or a locked one was cancelled). The shell
    /// only hears about holds through the hotkey, so this is how it learns to leave its listening state.
    public var onLatchEnded: (@MainActor () -> Void)?

    /// Recording hands-free after a tap.
    public private(set) var holdLatched = false
    /// The press that ends a locked recording is down; its release finishes.
    private var finishingLock = false
    private var lockTimeout: Task<Void, Never>?
    private var holdBeganAt: Date?

    /// Core Audio UID of the microphone, nil for the system default. Persisted.
    public var microphoneUID: String? {
        get { recorder.deviceUID }
        set {
            recorder.deviceUID = newValue
            defaults.set(newValue, forKey: Self.microphoneDefaultsKey)
        }
    }

    /// Display name for the engine popup.
    public var engineName: String { transcriber.displayName }

    /// Detail line for the selected engine.
    public var modelStatus: String { engineDetail(engine) }

    /// Localised name for a supported language code.
    public static func languageName(_ code: String) -> String {
        Locale.current.localizedString(forLanguageCode: code)?.capitalized ?? code.uppercased()
    }

    /// ISO 639-1 language hint for the engine. Persisted. Defaults to the system language when supported, else English.
    public var language: String {
        get {
            if let stored = defaults.string(forKey: Self.languageDefaultsKey),
               transcriber.supportedLanguages.contains(stored) {
                return stored
            }
            let system = Locale.current.language.languageCode?.identifier ?? "en"
            return transcriber.supportedLanguages.contains(system) ? system : "en"
        }
        set {
            defaults.set(newValue, forKey: Self.languageDefaultsKey)
            onStatus?(statusLine)
        }
    }

    public var supportedLanguages: [String] { transcriber.supportedLanguages }

    /// "Parakeet v3 · EN" style line for the panel.
    private var statusLine: String { "\(transcriber.displayName) · \(language.uppercased())" }

    private let parakeet: any Transcriber
    private let apple: any Transcriber
    private var transcriber: any Transcriber { engine == .apple ? apple : parakeet }
    private let recorder: any VoiceRecording
    private let microphonePermission: @MainActor () -> Permissions.MicrophoneStatus
    private let now: @MainActor () -> Date
    private let defaults: UserDefaults
    private var context: ToolContext?
    /// The newest transcription. Each one waits for the one before, so dictations are emitted in order.
    private var job: Task<Void, Never>?

    public init(
        parakeet: any Transcriber = ParakeetTranscriber(),
        apple: any Transcriber = AppleTranscriber(),
        defaults: UserDefaults = .standard,
        recorder: (any VoiceRecording)? = nil,
        microphonePermission: @escaping @MainActor () -> Permissions.MicrophoneStatus = { Permissions.microphone },
        now: @escaping @MainActor () -> Date = { Date() },
        lockLimit: Duration = VoiceTool.defaultLockLimit,
        transcribeLimit: Duration = VoiceTool.defaultTranscribeLimit
    ) {
        self.parakeet = parakeet
        self.apple = apple
        self.defaults = defaults
        let recorder = recorder ?? MicRecorder()
        self.recorder = recorder
        self.microphonePermission = microphonePermission
        self.now = now
        self.lockLimit = lockLimit
        self.transcribeLimit = transcribeLimit
        engine = defaults.string(forKey: Self.engineDefaultsKey).flatMap(VoiceEngine.init(rawValue:)) ?? .parakeet
        if defaults.object(forKey: Self.holdKeyDefaultsKey) != nil,
           let key = ModifierKey(rawValue: UInt16(clamping: defaults.integer(forKey: Self.holdKeyDefaultsKey))) {
            holdKey = key
        } else {
            holdKey = .rightOption
        }
        recorder.deviceUID = defaults.string(forKey: Self.microphoneDefaultsKey)
        skipFillers = defaults.object(forKey: Self.skipFillersDefaultsKey) == nil
            || defaults.bool(forKey: Self.skipFillersDefaultsKey)
        spokenPunctuation = defaults.bool(forKey: Self.spokenPunctuationDefaultsKey)
        sayToSend = defaults.bool(forKey: Self.sayToSendDefaultsKey)
        numbersAsDigits = defaults.object(forKey: Self.numbersAsDigitsDefaultsKey) == nil
            || defaults.bool(forKey: Self.numbersAsDigitsDefaultsKey)
        tapToLock = defaults.bool(forKey: Self.tapToLockDefaultsKey)
        let stored = defaults.data(forKey: Self.dictionaryDefaultsKey)
            .flatMap { try? JSONDecoder().decode([WordReplacement].self, from: $0) } ?? []
        dictionary = stored
        replacements = WordReplacements(stored)
        recorder.onInterrupted = { [weak self] in self?.recordingInterrupted() }
    }

    public func attach(_ context: ToolContext) {
        self.context = context
    }

    /// Downloads and loads the model in the background so the first dictation is not stuck waiting.
    /// Apple Speech has nothing to load, and asking for its permission waits for the first dictation.
    public func warmUp() {
        guard engine == .parakeet else {
            onStatus?(statusLine)
            return
        }
        onStatus?("\(transcriber.displayName) · loading")
        // An unload queued by `deactivate` runs first, so it cannot drop the models this loads.
        let pending = job
        Task { [transcriber, self] in
            await pending?.value
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

    public func activate() {
        warmUp()
    }

    /// Drops a dictation in progress, lets a queued transcription finish, then frees the models.
    public func deactivate() {
        if recorder.isRecording {
            _ = recorder.stop()
            context?.overlay.hide()
        }
        endLock()
        let previous = job
        job = Task { [parakeet, apple] in
            await previous?.value
            await parakeet.unload()
            await apple.unload()
        }
    }

    public func holdBegan() {
        guard let context else { return }
        if holdLatched {
            finishingLock = true
            return
        }
        switch microphonePermission() {
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
        holdBeganAt = now()
        lockTimeout?.cancel()
        lockTimeout = Task { [weak self, lockLimit] in
            try? await Task.sleep(for: lockLimit)
            guard !Task.isCancelled, let self, self.recorder.isRecording else { return }
            log.info("recording reached its limit")
            finishRecording()
            onLatchEnded?()
        }
        let recorder = recorder
        context.overlay.showListening { recorder.currentLevel }
    }

    public func holdEnded() {
        guard context != nil, recorder.isRecording else { return }
        if holdLatched {
            // The release of the tap that locked it changes nothing; the next tap's release finishes.
            guard finishingLock else { return }
        } else if tapToLock, let began = holdBeganAt, now().timeIntervalSince(began) < Self.minimumHold {
            log.info("tap: recording locked")
            holdLatched = true
            return
        }
        finishRecording()
    }

    /// The microphone went away mid-recording: what was captured is transcribed, as if the key had been released.
    private func recordingInterrupted() {
        log.info("recording interrupted")
        finishRecording()
        onLatchEnded?()
    }

    private func finishRecording() {
        guard let context else { return }
        endLock()
        let samples = recorder.stop()
        let duration = Double(samples.count) / MicRecorder.sampleRate
        log.info("recording stopped: \(samples.count) samples, \(duration, format: .fixed(precision: 2))s")
        guard duration >= Self.minimumHold else {
            context.overlay.hide()
            return
        }
        // A transcription still running from the previous hold finishes first; nothing is dropped.
        let previous = job
        let released = now()
        job = Task { [weak self] in
            await previous?.value
            await self?.transcribe(samples, duration: duration, emit: true, released: released)
        }
    }

    /// Drops a locked recording: nothing is transcribed or emitted. For Escape and the pill's close button.
    public func cancelLock() {
        guard holdLatched else { return }
        _ = recorder.stop()
        endLock()
        log.info("locked recording cancelled")
        context?.overlay.hide()
        onLatchEnded?()
    }

    public func holdCancelled() {
        guard let context, recorder.isRecording else { return }
        if holdLatched {
            // The key was part of a chord while locked: not the finishing tap.
            finishingLock = false
            return
        }
        endLock()
        _ = recorder.stop()
        log.info("recording dropped: the hold key was part of a chord")
        context.overlay.hide()
    }

    private func endLock() {
        holdLatched = false
        finishingLock = false
        lockTimeout?.cancel()
        lockTimeout = nil
    }

    // A new hold may have started while an older transcription was queued or running; its listening pill wins.
    private func show(_ state: PillState) {
        if !recorder.isRecording { context?.overlay.show(state) }
    }

    private func flash(_ state: PillState, for duration: Duration = .seconds(1.2)) {
        if !recorder.isRecording { context?.overlay.flash(state, for: duration) }
    }

    /// What a dictation becomes after the text passes.
    struct Polished: Equatable {
        /// Everything that was said, closing "send" included.
        let text: String
        /// Set when the dictation ended in "send": the text without it, for the paste that Return follows.
        let submitText: String?
    }

    /// The text passes after the filler filter. A closing "send" is split off first so the numbers, the marks
    /// and the dictionary see the body alone; the whole text gets the same passes for when nothing is sent.
    func polish(_ text: String) -> Polished {
        let body = sayToSend ? SpokenSend.parse(text) : SpokenSend.Parsed(text: text, submit: false)
        return Polished(text: passes(text), submitText: body.submit ? passes(body.text) : nil)
    }

    private func passes(_ text: String) -> String {
        var text = text
        if numbersAsDigits, language == "en" { text = SpokenNumbers.default.apply(text) }
        if spokenPunctuation { text = SpokenPunctuation.default.apply(text) }
        return replacements.apply(text)
    }

    #if DEBUG
    /// Runs the full transcription path on given samples but never emits a result (so nothing is pasted).
    /// Returns the transcript. Used by the demo mode to check the engine without a microphone.
    public func debugTranscribe(_ samples: [Float]) async -> String? {
        await transcribe(samples, duration: Double(samples.count) / MicRecorder.sampleRate, emit: false)
    }

    /// Returns once every queued transcription and unload has run. Tests only.
    func debugWaitForJobs() async {
        await job?.value
    }
    #endif

    @discardableResult
    private func transcribe(
        _ samples: [Float], duration: TimeInterval, emit: Bool, released: Date? = nil
    ) async -> String? {
        guard let context else { return nil }
        let engine = transcriber.displayName
        show(.transcribing(detail: engine))
        do {
            try await transcriber.prepare { message in
                Task { @MainActor [weak self] in self?.show(.preparing(message)) }
            }
            if Task.isCancelled { return nil }
            if case .preparing = context.overlay.state {
                show(.transcribing(detail: engine))
            }
            let language = language
            let transcript = try await Self.transcribe(
                samples, language: language, with: transcriber, limit: transcribeLimit + .seconds(duration)
            )
            if Task.isCancelled { return nil }
            let text = skipFillers ? FillerFilter.forLanguage(language).clean(transcript.text) : transcript.text
            if text != transcript.text {
                log.info("fillers stripped: \(transcript.text.count) -> \(text.count) chars")
            }
            let polished = polish(text)
            guard !polished.text.isEmpty else {
                flash(.failed("Nothing heard"))
                return nil
            }
            if emit, let released, now().timeIntervalSince(released) > Self.staleAfter {
                // Too late to paste (and to press Return): the front app is no longer the one that was dictated
                // into. Still goes through the pipeline so history and Recent keep it; the pipeline copies it.
                log.info("transcript ready \(self.now().timeIntervalSince(released), format: .fixed(precision: 1))s after release, copied instead")
                context.emit(ToolResult(
                    toolID: id, text: polished.text, duration: duration,
                    copyInsteadOfPaste: "Took too long, transcript copied"
                ))
            } else if emit {
                context.emit(ToolResult(
                    toolID: id, text: polished.text, duration: duration, submitText: polished.submitText
                ))
            }
            return polished.text
        } catch {
            log.error("transcription failed: \(String(describing: error), privacy: .public)")
            if let described = error as? any LocalizedError, let message = described.errorDescription {
                flash(.failed(message), for: .seconds(4))
            } else {
                flash(.failed("Transcription failed"), for: .seconds(2))
            }
            return nil
        }
    }

    /// Runs one recognition and throws `transcriptionTimedOut` when it is not done within `limit`. The engine is
    /// cancelled then, but not waited for: a hung one would hold the queue just the same.
    private static func transcribe(
        _ samples: [Float], language: String, with transcriber: any Transcriber, limit: Duration
    ) async throws -> Transcript {
        try await withCheckedThrowingContinuation { continuation in
            let race = Race(continuation)
            let work = Task {
                do {
                    race.finish(.success(try await transcriber.transcribe(samples: samples, language: language)))
                } catch {
                    race.finish(.failure(error))
                }
            }
            Task {
                try? await Task.sleep(for: limit)
                if race.finish(.failure(VoiceToolError.transcriptionTimedOut)) { work.cancel() }
            }
        }
    }

    /// Resumes the continuation for whichever of the recognition and its timeout comes first.
    private final class Race: Sendable {
        private let continuation: Mutex<CheckedContinuation<Transcript, any Error>?>

        init(_ continuation: CheckedContinuation<Transcript, any Error>) {
            self.continuation = Mutex(continuation)
        }

        /// True when this call was the first.
        @discardableResult
        func finish(_ result: Result<Transcript, any Error>) -> Bool {
            let continuation = continuation.withLock { current in
                defer { current = nil }
                return current
            }
            continuation?.resume(with: result)
            return continuation != nil
        }
    }
}
