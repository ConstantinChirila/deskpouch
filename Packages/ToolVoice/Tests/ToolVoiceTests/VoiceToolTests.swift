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
        #expect(polished == .init(text: "Is Deskpouch ready?", submit: true))
    }

    @Test func numbersBecomeDigitsInEnglishOnly() {
        let tool = tool()
        tool.language = "en"
        #expect(tool.polish("It costs twenty five dollars.").text == "It costs $25.")
        tool.numbersAsDigits = false
        #expect(tool.polish("It costs twenty five dollars.").text == "It costs twenty five dollars.")
    }

    @Test func polishLeavesTextAloneByDefault() {
        let polished = tool().polish("Hello comma world. Send.")
        #expect(polished == .init(text: "Hello comma world. Send.", submit: false))
    }

    @Test func textOptionsPersist() {
        let suite = "voice-text-options-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = VoiceTool(parakeet: StubTranscriber(), apple: StubTranscriber(), defaults: defaults)
        #expect(!first.spokenPunctuation && !first.sayToSend && !first.tapToLock && first.dictionary.isEmpty)
        first.spokenPunctuation = true
        first.sayToSend = true
        first.tapToLock = true
        first.dictionary = [WordReplacement(heard: "a", written: "b")]
        let second = VoiceTool(parakeet: StubTranscriber(), apple: StubTranscriber(), defaults: defaults)
        #expect(second.spokenPunctuation && second.sayToSend && second.tapToLock)
        #expect(second.dictionary.map(\.heard) == ["a"])
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
