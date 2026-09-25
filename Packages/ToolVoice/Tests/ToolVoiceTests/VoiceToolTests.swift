import DeskpouchCore
import Foundation
import Testing
@testable import ToolVoice

/// Returns fixed text, no model or microphone involved.
final class StubTranscriber: Transcriber, @unchecked Sendable {
    let displayName: String
    let supportedLanguages: [String]
    var text: String
    private(set) var languages: [String?] = []
    private(set) var unloads = 0

    init(_ name: String = "Stub", languages: [String] = ["en", "de"], text: String = "hello") {
        displayName = name
        supportedLanguages = languages
        self.text = text
    }

    /// Set before use: `prepare` waits here until `finishPreparing()`, like a model download.
    var preparingStalls = false
    /// Set before use: `transcribe` never returns.
    var transcribeHangs = false
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private let lock = NSLock()

    func prepare(status: @escaping @Sendable (String) -> Void) async throws {
        guard preparingStalls else { return }
        await withCheckedContinuation { continuation in
            lock.withLock { waiting.append(continuation) }
        }
    }

    var isPreparing: Bool { lock.withLock { !waiting.isEmpty } }

    func finishPreparing() {
        let continuations = lock.withLock {
            defer { waiting = [] }
            return waiting
        }
        preparingStalls = false
        for continuation in continuations { continuation.resume() }
    }

    func unload() async {
        unloads += 1
    }

    func transcribe(samples: [Float], language: String?) async throws -> Transcript {
        languages.append(language)
        if transcribeHangs { await withCheckedContinuation { (_: CheckedContinuation<Void, Never>) in } }
        return Transcript(text: text, processingTime: 0)
    }
}

/// A microphone that records `seconds` of silence.
@MainActor
final class FakeRecorder: VoiceRecording {
    var deviceUID: String?
    private(set) var isRecording = false
    let currentLevel: Float = 0
    var onInterrupted: (@MainActor () -> Void)?
    private(set) var starts = 0
    var seconds = 1.0

    func start() throws {
        isRecording = true
        starts += 1
    }

    func stop() -> [Float] {
        guard isRecording || interrupted else { return [] }
        isRecording = false
        interrupted = false
        return [Float](repeating: 0, count: Int(seconds * 16_000))
    }

    private var interrupted = false

    /// The microphone goes away: capture stops, the samples stay for `stop()`.
    func interrupt() {
        isRecording = false
        interrupted = true
        onInterrupted?()
    }
}

@MainActor
final class FakeClock {
    var date = Date(timeIntervalSince1970: 0)
    func advance(_ seconds: TimeInterval) { date += seconds }
}

@MainActor
struct VoiceToolTests {
    private let defaults: UserDefaults

    init() {
        let suite = "ToolVoiceTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
    }

    private func tool(parakeet: StubTranscriber = StubTranscriber(), apple: StubTranscriber = StubTranscriber("Apple", languages: ["fr"])) -> VoiceTool {
        VoiceTool(parakeet: parakeet, apple: apple, defaults: defaults)
    }

    private func attach(_ tool: VoiceTool) -> (ToolContext, () -> [ToolResult]) {
        var emitted: [ToolResult] = []
        let context = ToolContext(overlay: OverlayController(), emit: { emitted.append($0) })
        tool.attach(context)
        return (context, { emitted })
    }

    @Test func defaultsWhenNothingIsStored() {
        let tool = tool()
        #expect(tool.engine == .parakeet)
        #expect(tool.holdKey == .rightOption)
        #expect(tool.skipFillers)
    }

    @Test func settingsPersist() {
        let first = tool()
        first.skipFillers = false
        first.holdKey = .leftOption
        first.engine = .apple
        let second = tool()
        #expect(!second.skipFillers)
        #expect(second.holdKey == .leftOption)
        #expect(second.engine == .apple)
    }

    @Test func storedLanguageIsUsedWhenTheEngineSupportsIt() {
        let tool = tool()
        tool.language = "de"
        #expect(tool.language == "de")
    }

    @Test func languageFallsBackWhenStoredCodeIsUnsupportedByEngine() {
        defaults.set("xx", forKey: VoiceTool.languageDefaultsKey)
        let tool = tool(parakeet: StubTranscriber(languages: ["en"]))
        #expect(tool.language == "en")
    }

    @Test func switchingEngineRechecksTheStoredLanguage() {
        let tool = tool()
        tool.language = "de"
        tool.engine = .apple
        // Apple stub supports only French, and neither "de" nor English.
        let system = Locale.current.language.languageCode?.identifier ?? "en"
        #expect(tool.language == (system == "fr" ? "fr" : "en"))
    }

    @Test func transcriptIsCleanedAndPassesLanguage() async {
        let parakeet = StubTranscriber(text: "um hello there")
        let tool = tool(parakeet: parakeet)
        tool.language = "en"
        _ = attach(tool)
        let text = await tool.debugTranscribe([Float](repeating: 0, count: 16_000))
        #expect(text == "Hello there")
        #expect(parakeet.languages == ["en"])
    }

    @Test func fillersFollowTheLanguage() async {
        let parakeet = StubTranscriber(text: "Äh, er kommt um fünf.")
        let tool = tool(parakeet: parakeet)
        tool.language = "de"
        _ = attach(tool)
        #expect(await tool.debugTranscribe([Float](repeating: 0, count: 16_000)) == "Er kommt um fünf.")
        #expect(parakeet.languages == ["de"])

        parakeet.text = "um, he is in the ER with a 35 mm lens."
        tool.language = "en"
        #expect(await tool.debugTranscribe([Float](repeating: 0, count: 16_000)) == "He is in the ER with a 35 mm lens.")
    }

    @Test func fillerOnlyTranscriptIsDropped() async {
        let tool = tool(parakeet: StubTranscriber(text: "um uh"))
        let (_, emitted) = attach(tool)
        let text = await tool.debugTranscribe([Float](repeating: 0, count: 16_000))
        #expect(text == nil)
        #expect(emitted().isEmpty)
    }

    @Test func fillersAreKeptWhenSkippingIsOff() async {
        let tool = tool(parakeet: StubTranscriber(text: "um hello"))
        tool.skipFillers = false
        _ = attach(tool)
        #expect(await tool.debugTranscribe([Float](repeating: 0, count: 16_000)) == "um hello")
    }

    @Test func polishRunsSendThenMarksThenDictionary() {
        let tool = tool()
        tool.sayToSend = true
        tool.spokenPunctuation = true
        tool.dictionary = [WordReplacement(heard: "desk pouch", written: "Deskpouch")]
        let polished = tool.polish("Is desk pouch ready question mark. Send.")
        #expect(polished == .init(text: "Is Deskpouch ready? Send.", submitText: "Is Deskpouch ready?"))
    }

    @Test func numbersBecomeDigitsInEnglishOnly() {
        let tool = tool()
        tool.language = "en"
        #expect(tool.polish("It costs twenty five dollars.").text == "It costs $25.")
        tool.numbersAsDigits = false
        #expect(tool.polish("It costs twenty five dollars.").text == "It costs twenty five dollars.")
        tool.numbersAsDigits = true
        tool.language = "de"
        #expect(tool.polish("It costs twenty five dollars.").text == "It costs twenty five dollars.")
    }

    @Test func aLoneSendKeepsItsWordForWhenNothingIsSent() {
        let tool = tool()
        tool.sayToSend = true
        #expect(tool.polish("Send.") == .init(text: "Send.", submitText: ""))
    }

    @Test func polishLeavesTextAloneByDefault() {
        let polished = tool().polish("Hello comma world. Send.")
        #expect(polished == .init(text: "Hello comma world. Send.", submitText: nil))
    }

    @Test func textOptionsPersist() {
        let suite = "voice-text-options-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = VoiceTool(parakeet: StubTranscriber(), apple: StubTranscriber(), defaults: defaults)
        #expect(!first.spokenPunctuation && !first.sayToSend && !first.tapToLock && first.dictionary.isEmpty)
        #expect(first.numbersAsDigits)
        first.numbersAsDigits = false
        first.spokenPunctuation = true
        first.sayToSend = true
        first.tapToLock = true
        first.dictionary = [WordReplacement(heard: "a", written: "b")]
        let second = VoiceTool(parakeet: StubTranscriber(), apple: StubTranscriber(), defaults: defaults)
        #expect(second.spokenPunctuation && second.sayToSend && second.tapToLock)
        #expect(second.dictionary.map(\.heard) == ["a"])
        #expect(!second.numbersAsDigits)
    }

    // MARK: Tap to lock

    private func lockable(
        _ recorder: FakeRecorder, _ clock: FakeClock, tapToLock: Bool = true, lockLimit: Duration = .seconds(600),
        parakeet: StubTranscriber = StubTranscriber(), transcribeLimit: Duration = .seconds(60)
    ) -> VoiceTool {
        let tool = VoiceTool(
            parakeet: parakeet, apple: StubTranscriber(), defaults: defaults, recorder: recorder,
            microphonePermission: { .granted }, now: { clock.date }, lockLimit: lockLimit,
            transcribeLimit: transcribeLimit
        )
        tool.tapToLock = tapToLock
        return tool
    }

    @Test func aHoldRecordsAndEmitsOnRelease() async {
        let (recorder, clock) = (FakeRecorder(), FakeClock())
        let tool = lockable(recorder, clock)
        let (_, emitted) = attach(tool)
        tool.holdBegan()
        clock.advance(1)
        tool.holdEnded()
        #expect(!tool.holdLatched && !recorder.isRecording)
        await tool.debugWaitForJobs()
        #expect(emitted().map(\.text) == ["hello"])
    }

    @Test func aTapLocksAndTheNextTapFinishes() async {
        let (recorder, clock) = (FakeRecorder(), FakeClock())
        let tool = lockable(recorder, clock)
        let (_, emitted) = attach(tool)
        tool.holdBegan()
        clock.advance(0.1)
        tool.holdEnded()
        #expect(tool.holdLatched && recorder.isRecording)

        clock.advance(5)
        tool.holdBegan()
        #expect(recorder.starts == 1)
        #expect(tool.holdLatched)
        tool.holdEnded()
        #expect(!tool.holdLatched && !recorder.isRecording)
        await tool.debugWaitForJobs()
        #expect(emitted().count == 1)
    }

    @Test func aTapWithoutTapToLockIsDropped() async {
        let (recorder, clock) = (FakeRecorder(), FakeClock())
        let tool = lockable(recorder, clock, tapToLock: false)
        let (_, emitted) = attach(tool)
        recorder.seconds = 0.1
        tool.holdBegan()
        clock.advance(0.1)
        tool.holdEnded()
        #expect(!tool.holdLatched && !recorder.isRecording)
        await tool.debugWaitForJobs()
        #expect(emitted().isEmpty)
    }

    @Test func aChordWhileLockedDoesNotFinish() {
        let (recorder, clock) = (FakeRecorder(), FakeClock())
        let tool = lockable(recorder, clock)
        _ = attach(tool)
        tool.holdBegan()
        tool.holdEnded()
        tool.holdBegan()
        tool.holdCancelled()
        #expect(tool.holdLatched && recorder.isRecording)
        // The chord's own release never arrives (`HotkeyPhase.cancelled`); a stray one must not finish either.
        tool.holdEnded()
        #expect(tool.holdLatched && recorder.isRecording)
    }

    @Test func deactivateClearsTheLock() async {
        let (recorder, clock) = (FakeRecorder(), FakeClock())
        let tool = lockable(recorder, clock)
        let (_, emitted) = attach(tool)
        tool.holdBegan()
        tool.holdEnded()
        tool.deactivate()
        #expect(!tool.holdLatched && !recorder.isRecording)
        await tool.debugWaitForJobs()
        #expect(emitted().isEmpty)
    }

    @Test func theLimitFinishesAndTellsTheShell() async {
        let (recorder, clock) = (FakeRecorder(), FakeClock())
        let tool = lockable(recorder, clock, lockLimit: .milliseconds(20))
        let (_, emitted) = attach(tool)
        var ended = 0
        tool.onLatchEnded = { ended += 1 }
        tool.holdBegan()
        tool.holdEnded()
        #expect(tool.holdLatched)
        for _ in 0..<200 where tool.holdLatched { try? await Task.sleep(for: .milliseconds(10)) }
        #expect(!tool.holdLatched && !recorder.isRecording)
        #expect(ended == 1)
        await tool.debugWaitForJobs()
        #expect(emitted().count == 1)
    }

    @Test func finishingByTapDoesNotReportALatchEnd() {
        let (recorder, clock) = (FakeRecorder(), FakeClock())
        let tool = lockable(recorder, clock)
        _ = attach(tool)
        var ended = 0
        tool.onLatchEnded = { ended += 1 }
        tool.holdBegan()
        tool.holdEnded()
        tool.holdBegan()
        tool.holdEnded()
        #expect(ended == 0)
    }

    @Test func aPlainHoldAlsoEndsAtTheLimit() async {
        let (recorder, clock) = (FakeRecorder(), FakeClock())
        let tool = lockable(recorder, clock, tapToLock: false, lockLimit: .milliseconds(20))
        let (_, emitted) = attach(tool)
        var ended = 0
        tool.onLatchEnded = { ended += 1 }
        tool.holdBegan()
        for _ in 0..<200 where recorder.isRecording { try? await Task.sleep(for: .milliseconds(10)) }
        #expect(!recorder.isRecording)
        #expect(ended == 1)
        await tool.debugWaitForJobs()
        #expect(emitted().count == 1)
        // The release that went missing turns up after all.
        tool.holdEnded()
        await tool.debugWaitForJobs()
        #expect(emitted().count == 1)
    }

    @Test func cancelLockDropsTheRecording() async {
        let (recorder, clock) = (FakeRecorder(), FakeClock())
        let tool = lockable(recorder, clock)
        let (_, emitted) = attach(tool)
        var ended = 0
        tool.onLatchEnded = { ended += 1 }
        tool.holdBegan()
        tool.holdEnded()
        #expect(tool.holdLatched)
        tool.cancelLock()
        #expect(!tool.holdLatched && !recorder.isRecording)
        #expect(ended == 1)
        await tool.debugWaitForJobs()
        #expect(emitted().isEmpty)
        // The next hold records as usual.
        tool.holdBegan()
        clock.advance(1)
        tool.holdEnded()
        await tool.debugWaitForJobs()
        #expect(emitted().count == 1)
    }

    @Test func cancelLockDoesNothingToAPlainHold() {
        let (recorder, clock) = (FakeRecorder(), FakeClock())
        let tool = lockable(recorder, clock)
        _ = attach(tool)
        var ended = 0
        tool.onLatchEnded = { ended += 1 }
        tool.holdBegan()
        tool.cancelLock()
        #expect(recorder.isRecording)
        #expect(ended == 0)
    }

    @Test func anInterruptedRecordingIsTranscribed() async {
        let (recorder, clock) = (FakeRecorder(), FakeClock())
        let tool = lockable(recorder, clock)
        let (_, emitted) = attach(tool)
        var ended = 0
        tool.onLatchEnded = { ended += 1 }
        tool.holdBegan()
        recorder.interrupt()
        #expect(ended == 1)
        await tool.debugWaitForJobs()
        #expect(emitted().count == 1)
    }

    // MARK: Late transcripts

    /// Late: still emitted (history and Recent keep it), whole ("send" not stripped, no Return), marked so the
    /// pipeline copies instead of pasting.
    @Test func aTranscriptThatComesLateIsCopiedNotPasted() async {
        let (recorder, clock) = (FakeRecorder(), FakeClock())
        let parakeet = StubTranscriber(text: "hello send")
        parakeet.preparingStalls = true
        let tool = lockable(recorder, clock, parakeet: parakeet)
        tool.sayToSend = true
        let (_, emitted) = attach(tool)
        tool.holdBegan()
        clock.advance(1)
        tool.holdEnded()
        for _ in 0..<200 where !parakeet.isPreparing { try? await Task.sleep(for: .milliseconds(5)) }
        clock.advance(VoiceTool.staleAfter + 1)
        parakeet.finishPreparing()
        await tool.debugWaitForJobs()
        let results = emitted()
        #expect(results.map(\.text) == ["hello send"])
        #expect(results.first?.submitText == nil)
        #expect(results.first?.copyInsteadOfPaste != nil)
    }

    @Test func aTranscriptWithinTheLimitIsEmitted() async {
        let (recorder, clock) = (FakeRecorder(), FakeClock())
        let parakeet = StubTranscriber()
        parakeet.preparingStalls = true
        let tool = lockable(recorder, clock, parakeet: parakeet)
        let (_, emitted) = attach(tool)
        tool.holdBegan()
        clock.advance(1)
        tool.holdEnded()
        for _ in 0..<200 where !parakeet.isPreparing { try? await Task.sleep(for: .milliseconds(5)) }
        clock.advance(VoiceTool.staleAfter - 1)
        parakeet.finishPreparing()
        await tool.debugWaitForJobs()
        #expect(emitted().map(\.text) == ["hello"])
        #expect(emitted().first?.copyInsteadOfPaste == nil)
    }

    @Test func aHungRecognitionTimesOutAndTheQueueMovesOn() async {
        let (recorder, clock) = (FakeRecorder(), FakeClock())
        let parakeet = StubTranscriber()
        parakeet.transcribeHangs = true
        recorder.seconds = 0.5
        let tool = lockable(recorder, clock, tapToLock: false, parakeet: parakeet, transcribeLimit: .milliseconds(20))
        let (_, emitted) = attach(tool)
        tool.holdBegan()
        tool.holdEnded()
        tool.holdBegan()
        tool.holdEnded()
        // Only the first recognition hangs.
        for _ in 0..<400 where parakeet.languages.isEmpty { try? await Task.sleep(for: .milliseconds(5)) }
        parakeet.transcribeHangs = false
        await tool.debugWaitForJobs()
        #expect(emitted().map(\.text) == ["hello"])
        #expect(parakeet.languages.count == 2)
    }

    @Test func debugTranscribeNeverEmits() async {
        let tool = tool()
        let (_, emitted) = attach(tool)
        #expect(await tool.debugTranscribe([Float](repeating: 0, count: 16_000)) == "hello")
        #expect(emitted().isEmpty)
    }

    @Test func deactivateUnloadsBothEngines() async {
        let parakeet = StubTranscriber()
        let apple = StubTranscriber("Apple", languages: ["fr"])
        let tool = tool(parakeet: parakeet, apple: apple)
        _ = attach(tool)
        tool.deactivate()
        await tool.debugWaitForJobs()
        #expect(parakeet.unloads == 1)
        #expect(apple.unloads == 1)
    }
}
