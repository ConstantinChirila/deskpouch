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
        /// Return was pressed after the paste (a dictation that ended in "send").
        public var submitted = false
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
    private let thumbsDirectory: URL
    /// Ends when the delivery now holding the clipboard is done with it. Deliveries start independently (two
    /// dictations can finish close together) but share one pasteboard and one paste target, so copy, paste,
    /// Return and the restore of one delivery finish before the next one's start.
    private var clipboardTurn: Task<Void, Never>?

    public init(effects: any OutputEffects, history: HistoryStore?, thumbsDirectory: URL = HistoryThumbnails.defaultDirectory) {
        self.effects = effects
        self.history = history
        self.thumbsDirectory = thumbsDirectory
    }

    /// Folder used when a config has none.
    public static var defaultFolder: URL {
        FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask)[0]
            .appending(path: "Deskpouch", directoryHint: .isDirectory)
    }

    public func deliver(_ result: ToolResult, config: ToolOutputConfig) async -> Delivery {
        var config = config
        if result.copyInsteadOfPaste != nil, config.actions.contains(.paste) {
            config.actions.remove(.paste)
            config.actions.insert(.copy)
        }
        var delivery = Delivery()
        let fullText = result.text.flatMap { $0.isEmpty ? nil : $0 }
        // A closing "send" only comes off when the text is going to be pasted and sent.
        let submitting = result.submitText != nil && config.actions.contains(.paste)
        var text = submitting ? result.submitText.flatMap { $0.isEmpty ? nil : $0 } : fullText
        var pasteboardSnapshot: (any Sendable)?
        // A file that is about to be moved by Save is copied afterwards, so the pasteboard points at its final
        // home. An image result is copied as pixel data straight away instead: it does not reference the file
        // path, so it does not need to wait for Save to finish moving it.
        let copyFileAfterSave = result.fileURL != nil && text == nil && result.image == nil
            && config.actions.contains(.copy) && config.actions.contains(.saveToFolder)

        let previousTurn = clipboardTurn
        let (turn, turnEnd) = AsyncStream<Never>.makeStream()
        clipboardTurn = Task { for await _ in turn {} }
        await previousTurn?.value
        var holdsClipboard = true
        // Copy and paste come first in `executionOrder`; the turn ends before the slow actions (a shell command
        // may run for 30 s), so they never hold up the next delivery's paste.
        func endClipboardTurn() async {
            guard holdsClipboard else { return }
            holdsClipboard = false
            if let snapshot = pasteboardSnapshot {
                pasteboardSnapshot = nil
                await effects.restorePasteboard(snapshot)
            }
            turnEnd.finish()
        }

        for action in OutputAction.executionOrder where config.actions.contains(action) {
            if action != .copy, action != .paste { await endClipboardTurn() }
            switch action {
            case .copy:
                if let text {
                    effects.copyText(text)
                } else if let image = result.image {
                    // When the result also has a file (a screenshot: the tool already wrote these exact pixels
                    // to its staging file before emitting), reuse those bytes instead of re-encoding the PNG a
                    // second time; `.copy` always runs before `.saveToFolder` (`executionOrder`), so the file is
                    // still at `result.fileURL`, not yet moved.
                    let pngData = result.fileURL.flatMap { try? Data(contentsOf: $0) }
                    effects.copyImage(image, pngData: pngData)
                } else if let file = result.fileURL, !copyFileAfterSave {
                    effects.copyFile(file)
                } else {
                    continue
                }
                delivery.copied = true

            case .paste:
                guard let pasted = text else {
                    // A dictation that was only "send": nothing to paste, the draft already in the field goes.
                    if submitting {
                        delivery.submitted = await effects.pressReturn()
                        if !delivery.submitted { text = fullText }
                    }
                    continue
                }
                let copiedForPaste = !delivery.copied
                if copiedForPaste {
                    // ⌘V reads the pasteboard, so the text has to go there; put the old contents back afterwards.
                    pasteboardSnapshot = effects.snapshotPasteboard()
                    effects.copyText(pasted)
                }
                delivery.pastedInto = await effects.pasteIntoFrontmostApp()
                if delivery.pastedInto == nil {
                    // Nothing took the paste, so nothing is sent either: the closing word goes back in.
                    if submitting, let fullText {
                        text = fullText
                        effects.copyText(fullText)
                    }
                    if copiedForPaste {
                        // Leave the text on the pasteboard rather than lose it.
                        pasteboardSnapshot = nil
                        delivery.copied = true
                        delivery.ran.append(.copy)
                    }
                } else if submitting {
                    delivery.submitted = await effects.pressReturn()
                }

            case .saveToFolder:
                guard text != nil || result.fileURL != nil else { continue }
                do {
                    delivery.savedTo = try effects.save(result, to: config.folder ?? Self.defaultFolder)
                } catch {
                    log.error("save failed: \(String(describing: error), privacy: .public)")
                    if copyFileAfterSave, let file = result.fileURL {
                        effects.copyFile(file)
                        delivery.copied = true
                        delivery.ran.append(.copy)
                    }
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
                // A dictation that was only "send" leaves nothing to log.
                guard text != nil || result.fileURL != nil || result.image != nil else { continue }
                let thumbURL = result.image.flatMap { HistoryThumbnails.write($0, id: result.id, to: thumbsDirectory) }
                do {
                    try history.record(HistoryItem(
                        id: result.id,
                        toolID: result.toolID,
                        createdAt: result.createdAt,
                        text: text,
                        fileURL: delivery.savedTo ?? result.fileURL,
                        duration: result.duration,
                        pastedInto: delivery.pastedInto,
                        kind: result.kind,
                        thumbURL: thumbURL,
                        meta: result.meta
                    ))
                    delivery.recorded = true
                } catch {
                    log.error("history record failed: \(String(describing: error), privacy: .public)")
                    if let thumbURL {
                        HistoryThumbnails.remove(thumbURL)
                    }
                    continue
                }
            }
            delivery.ran.append(action)
            if action == .saveToFolder, copyFileAfterSave, let saved = delivery.savedTo {
                effects.copyFile(saved)
                delivery.copied = true
                delivery.ran.append(.copy)
            }
        }

        await endClipboardTurn()
        return delivery
    }

    static func notificationBody(_ result: ToolResult, _ delivery: Delivery) -> String {
        if let target = delivery.pastedInto { return "Pasted into \(target)" }
        if let saved = delivery.savedTo { return "Saved \(saved.lastPathComponent)" }
        if let text = result.text, !text.isEmpty { return delivery.copied ? "Copied: \(text)" : text }
        return delivery.copied ? "Copied" : "Done"
    }
}
