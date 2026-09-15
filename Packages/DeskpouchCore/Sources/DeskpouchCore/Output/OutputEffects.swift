import AppKit
import Foundation
import UserNotifications
import os

private let log = Logger(subsystem: "com.constantinchirila.deskpouch", category: "output")

/// The side effects an `OutputPipeline` can cause. Injected so tests can record calls instead of touching the
/// pasteboard, the filesystem, or the frontmost app.
@MainActor
public protocol OutputEffects: AnyObject {
    /// What was on the pasteboard, so a paste without "copy" can put it back. Opaque to the pipeline.
    func snapshotPasteboard() -> (any Sendable)?
    func restorePasteboard(_ snapshot: any Sendable) async
    func copyText(_ text: String)
    func copyFile(_ url: URL)
    /// Posts ⌘V. Returns the target app's name, or nil when nothing could be pasted into.
    func pasteIntoFrontmostApp() async -> String?
    /// Writes `result` into `folder`; returns the saved file's URL.
    func save(_ result: ToolResult, to folder: URL) throws -> URL
    func revealInFinder(_ url: URL)
    func runShellCommand(_ command: String, result: ToolResult, savedFile: URL?) async
    func notify(title: String, body: String)
}

/// Real effects. Copy and paste through `Paster`, files through FileManager, notifications through UserNotifications.
@MainActor
public final class SystemOutputEffects: OutputEffects {
    public struct PasteboardSnapshot: Sendable {
        let items: [[String: Data]]
    }

    private var notificationsAuthorized = false

    public init() {}

    public func snapshotPasteboard() -> (any Sendable)? {
        guard let items = NSPasteboard.general.pasteboardItems, !items.isEmpty else { return nil }
        let copies = items.map { item in
            item.types.reduce(into: [String: Data]()) { acc, type in
                if let data = item.data(forType: type) { acc[type.rawValue] = data }
            }
        }
        return PasteboardSnapshot(items: copies)
    }

    public func restorePasteboard(_ snapshot: any Sendable) async {
        guard let snapshot = snapshot as? PasteboardSnapshot else { return }
        // The target app reads ⌘V asynchronously; give it time before the transcript disappears.
        try? await Task.sleep(for: .milliseconds(400))
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let items = snapshot.items.map { entry in
            let item = NSPasteboardItem()
            for (type, data) in entry {
                item.setData(data, forType: NSPasteboard.PasteboardType(type))
            }
            return item
        }
        pasteboard.writeObjects(items)
    }

    public func copyText(_ text: String) {
        Paster.copy(text)
    }

    public func copyFile(_ url: URL) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([url as NSURL])
    }

    public func pasteIntoFrontmostApp() async -> String? {
        // Give the pasteboard server a moment before the target app reads it.
        try? await Task.sleep(for: .milliseconds(40))
        return Paster.pasteIntoFrontmostApp()
    }

    public func save(_ result: ToolResult, to folder: URL) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if let source = result.fileURL {
            let destination = Self.uniqueURL(folder.appending(path: source.lastPathComponent))
            if source.deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL {
                return source
            }
            try FileManager.default.moveItem(at: source, to: destination)
            return destination
        }
        let stamp = Self.fileStamp.string(from: result.createdAt)
        let destination = Self.uniqueURL(folder.appending(path: "\(result.toolID) \(stamp).txt"))
        try (result.text ?? "").write(to: destination, atomically: true, encoding: .utf8)
        return destination
    }

    public func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    public func runShellCommand(_ command: String, result: ToolResult, savedFile: URL?) async {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        var env = ProcessInfo.processInfo.environment
        env["DESKPOUCH_TOOL"] = result.toolID
        env["DESKPOUCH_TEXT"] = result.text ?? ""
        env["DESKPOUCH_FILE"] = (savedFile ?? result.fileURL)?.path ?? ""
        process.environment = env
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            log.error("shell command failed to start: \(String(describing: error), privacy: .public)")
            return
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            process.terminationHandler = { _ in continuation.resume() }
        }
        log.info("shell command exited \(process.terminationStatus)")
    }

    public func notify(title: String, body: String) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        if notificationsAuthorized {
            Self.post(title: title, body: body)
            return
        }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            Task { @MainActor [weak self] in
                self?.notificationsAuthorized = granted
                if granted { Self.post(title: title, body: body) }
            }
        }
    }

    private static func post(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error { log.error("notification failed: \(String(describing: error), privacy: .public)") }
        }
    }

    private static let fileStamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return f
    }()

    private static func uniqueURL(_ url: URL) -> URL {
        var candidate = url
        var n = 2
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = url.deletingLastPathComponent().appending(path: "\(base) \(n)").appendingPathExtension(ext)
            n += 1
        }
        return candidate
    }
}
