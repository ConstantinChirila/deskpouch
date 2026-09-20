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

    func prepare(status: @escaping @Sendable (String) -> Void) async throws {}

    func unload() async {
        unloads += 1
    }

    func transcribe(samples: [Float], language: String?) async throws -> Transcript {
        languages.append(language)
        return Transcript(text: text, processingTime: 0)
    }
}

/// A microphone that records `seconds` of silence.
@MainActor
final class FakeRecorder: VoiceRecording {
    var deviceUID: String?
    private(set) var isRecording = false
    let currentLevel: Float = 0
    private(set) var starts = 0
    var seconds = 1.0

    func start() throws {
        isRecording = true
        starts += 1
    }

    func stop() -> [Float] {
        guard isRecording else { return [] }
        isRecording = false
        return [Float](repeating: 0, count: Int(seconds * 16_000))
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
        tool.language = "de"
        _ = attach(tool)
        let text = await tool.debugTranscribe([Float](repeating: 0, count: 16_000))
        #expect(text == "Hello there")
        #expect(parakeet.languages == ["de"])
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
        _ recorder: FakeRecorder, _ clock: FakeClock, tapToLock: Bool = true, lockLimit: Duration = .seconds(600)
    ) -> VoiceTool {
        let tool = VoiceTool(
            parakeet: StubTranscriber(), apple: StubTranscriber(), defaults: defaults, recorder: recorder,
            microphonePermission: { .granted }, now: { clock.date }, lockLimit: lockLimit
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
