import Foundation
import Testing
@testable import DeskpouchCore

/// Records every effect in call order instead of touching the system.
@MainActor
final class RecordingEffects: OutputEffects {
    var calls: [String] = []
    var pasteTarget: String? = "Slack"
    var savedURL = URL(fileURLWithPath: "/tmp/saved.txt")
    var pasteboardBefore: String? = "previous clipboard"

    func snapshotPasteboard() -> (any Sendable)? {
        calls.append("snapshot")
        return pasteboardBefore
    }
    func restorePasteboard(_ snapshot: any Sendable) async {
        calls.append("restore(\(snapshot as? String ?? "?"))")
    }
    func copyText(_ text: String) { calls.append("copyText") }
    func copyFile(_ url: URL) { calls.append("copyFile") }
    func pasteIntoFrontmostApp() async -> String? {
        calls.append("paste")
        return pasteTarget
    }
    func save(_ result: ToolResult, to folder: URL) throws -> URL {
        calls.append("save(\(folder.lastPathComponent))")
        return savedURL
    }
    func revealInFinder(_ url: URL) { calls.append("reveal(\(url.lastPathComponent))") }
    func runShellCommand(_ command: String, result: ToolResult, savedFile: URL?) async {
        calls.append("shell(\(command))")
    }
    func notify(title: String, body: String) { calls.append("notify(\(body))") }
}

@MainActor
struct OutputPipelineTests {
    @Test func runsInFixedOrderRegardlessOfSetOrder() async throws {
        let effects = RecordingEffects()
        let history = try HistoryStore.inMemory()
        let pipeline = OutputPipeline(effects: effects, history: history)
        let result = ToolResult(toolID: "voice", text: "hello", duration: 2)
        let config = ToolOutputConfig(actions: [.history, .notify, .paste, .copy])

        let delivery = await pipeline.deliver(result, config: config)

        #expect(effects.calls == ["copyText", "paste", "notify(Pasted into Slack)"])
        #expect(delivery.ran == [.copy, .paste, .notify, .history])
        #expect(delivery.copied)
        #expect(delivery.pastedInto == "Slack")
        #expect(delivery.notified)
        #expect(delivery.recorded)
        let logged = try history.recent(limit: 1)
        #expect(logged.map(\.text) == ["hello"])
        #expect(logged.first?.pastedInto == "Slack")
        #expect(logged.first?.id == result.id)
    }

    @Test func pasteWithoutCopyRestoresTheClipboard() async throws {
        let effects = RecordingEffects()
        let pipeline = OutputPipeline(effects: effects, history: nil)
        let result = ToolResult(toolID: "voice", text: "hello")

        let delivery = await pipeline.deliver(result, config: ToolOutputConfig(actions: [.paste]))

        #expect(effects.calls == ["snapshot", "copyText", "paste", "restore(previous clipboard)"])
        #expect(!delivery.copied)
        #expect(delivery.pastedInto == "Slack")
    }

    @Test func fileResultsSaveThenRevealThenShellThenNotify() async throws {
        let effects = RecordingEffects()
        let pipeline = OutputPipeline(effects: effects, history: nil)
        let result = ToolResult(toolID: "screen", fileURL: URL(fileURLWithPath: "/tmp/raw.mp4"), duration: 42)
        let config = ToolOutputConfig(
            actions: [.notify, .runShellCommand, .revealInFinder, .saveToFolder, .copy, .paste],
            folder: URL(fileURLWithPath: "/tmp/Out"),
            shellCommand: "echo hi"
        )

        let delivery = await pipeline.deliver(result, config: config)

        // Paste is skipped: nothing to paste for a file-only result.
        #expect(effects.calls == ["copyFile", "save(Out)", "reveal(saved.txt)", "shell(echo hi)", "notify(Saved saved.txt)"])
        #expect(delivery.ran == [.copy, .saveToFolder, .revealInFinder, .runShellCommand, .notify])
        #expect(delivery.savedTo == effects.savedURL)
    }

    @Test func historyOffMeansNothingLogged() async throws {
        let effects = RecordingEffects()
        let history = try HistoryStore.inMemory()
        let pipeline = OutputPipeline(effects: effects, history: history)
        _ = await pipeline.deliver(ToolResult(toolID: "voice", text: "secret"), config: ToolOutputConfig(actions: [.copy]))
        #expect(try history.count() == 0)
    }

    @Test func emptyTextDoesNothing() async throws {
        let effects = RecordingEffects()
        let pipeline = OutputPipeline(effects: effects, history: nil)
        let delivery = await pipeline.deliver(ToolResult(toolID: "voice", text: ""), config: ToolOutputConfig(actions: [.copy, .paste]))
        #expect(effects.calls.isEmpty)
        #expect(delivery.ran.isEmpty)
    }

    @Test func settingsPersistAndToggle() {
        let suite = "deskpouch-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = OutputSettings(defaults: defaults)
        settings.registerDefault(ToolOutputConfig(actions: [.copy, .paste, .history]), for: "voice")
        #expect(settings.config(for: "voice").actions == [.copy, .paste, .history])

        settings.toggle(.notify, for: "voice")
        settings.toggle(.paste, for: "voice")
        #expect(settings.config(for: "voice").actions == [.copy, .history, .notify])

        let reloaded = OutputSettings(defaults: defaults)
        reloaded.registerDefault(ToolOutputConfig(actions: [.copy]), for: "voice")
        #expect(reloaded.config(for: "voice").actions == [.copy, .history, .notify])
    }
}
