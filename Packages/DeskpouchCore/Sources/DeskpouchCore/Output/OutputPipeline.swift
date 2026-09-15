import Foundation
import os

private let log = Logger(subsystem: "com.constantinchirila.deskpouch", category: "output")

/// Runs a tool's chosen after-capture actions on a `ToolResult`, always in `OutputAction.executionOrder`.
/// Actions that need something the result lacks (paste without text, reveal without a file) are skipped.
@MainActor
public final class OutputPipeline {
    public struct Delivery: Sendable, Equatable {
        public var copied = false
        public var pastedInto: String?
        public var savedTo: URL?
        public var notified = false
        public var recorded = false
        /// Actions that were attempted, in the order they ran.
        public var ran: [OutputAction] = []
    }

    /// Filename-free description used in notifications and the Recent list.
    static let notificationTitle = "Deskpouch"

    private let effects: any OutputEffects
    private let history: HistoryStore?

    public init(effects: any OutputEffects, history: HistoryStore?) {
        self.effects = effects
        self.history = history
    }

    /// Folder used when a config has none.
    public static var defaultFolder: URL {
        FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask)[0]
            .appending(path: "Deskpouch", directoryHint: .isDirectory)
    }

    public func deliver(_ result: ToolResult, config: ToolOutputConfig) async -> Delivery {
        var delivery = Delivery()
        let text = result.text.flatMap { $0.isEmpty ? nil : $0 }
        var pasteboardSnapshot: (any Sendable)?

        for action in OutputAction.executionOrder where config.actions.contains(action) {
            switch action {
            case .copy:
                if let text {
                    effects.copyText(text)
                } else if let file = result.fileURL {
                    effects.copyFile(file)
                } else {
                    continue
                }
                delivery.copied = true

            case .paste:
                guard let text else { continue }
                if !delivery.copied {
                    // ⌘V reads the pasteboard, so the text has to go there; put the old contents back afterwards.
                    pasteboardSnapshot = effects.snapshotPasteboard()
                    effects.copyText(text)
                }
                delivery.pastedInto = await effects.pasteIntoFrontmostApp()

            case .saveToFolder:
                guard text != nil || result.fileURL != nil else { continue }
                do {
                    delivery.savedTo = try effects.save(result, to: config.folder ?? Self.defaultFolder)
                } catch {
                    log.error("save failed: \(String(describing: error), privacy: .public)")
                    continue
                }

            case .revealInFinder:
                guard let file = delivery.savedTo ?? result.fileURL else { continue }
                effects.revealInFinder(file)

            case .runShellCommand:
                guard let command = config.shellCommand, !command.isEmpty else { continue }
                await effects.runShellCommand(command, result: result, savedFile: delivery.savedTo)

            case .notify:
                effects.notify(title: Self.notificationTitle, body: Self.notificationBody(result, delivery))
                delivery.notified = true

            case .history:
                guard let history else { continue }
                do {
                    try history.record(HistoryItem(
                        id: result.id,
                        toolID: result.toolID,
                        createdAt: result.createdAt,
                        text: text,
                        fileURL: delivery.savedTo ?? result.fileURL,
                        duration: result.duration,
                        pastedInto: delivery.pastedInto
                    ))
                    delivery.recorded = true
                } catch {
                    log.error("history record failed: \(String(describing: error), privacy: .public)")
                    continue
                }
            }
            delivery.ran.append(action)
        }

        if let pasteboardSnapshot {
            await effects.restorePasteboard(pasteboardSnapshot)
        }
        return delivery
    }

    static func notificationBody(_ result: ToolResult, _ delivery: Delivery) -> String {
        if let target = delivery.pastedInto { return "Pasted into \(target)" }
        if let saved = delivery.savedTo { return "Saved \(saved.lastPathComponent)" }
        if let text = result.text, !text.isEmpty { return delivery.copied ? "Copied: \(text)" : text }
        return delivery.copied ? "Copied" : "Done"
    }
}
