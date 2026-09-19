import AppKit
import DeskpouchCore
import Foundation

/// What leaves the gallery when rows are copied or dragged out. Pure, so the rules are tested: files win, texts
/// are joined only when every row is text, and a row whose file is gone contributes nothing.
enum GalleryExport: Equatable {
    case files([URL])
    case text(String)
    case nothing

    /// ⌘C with several rows: every file; or, when no row has a file, the texts joined by blank lines.
    static func copy(_ items: [HistoryItem], missing: Set<UUID>) -> GalleryExport {
        let files = items.filter { !missing.contains($0.id) }.compactMap(\.fileURL)
        if !files.isEmpty { return .files(files) }
        let texts = items.compactMap(\.text).filter { !$0.isEmpty }
        return texts.isEmpty ? .nothing : .text(texts.joined(separator: "\n\n"))
    }

    /// A drag carries one pasteboard item per row: the file, or the row's text (a transcript, a colour's value).
    static func dragPayloads(_ items: [HistoryItem], missing: Set<UUID>) -> [Payload] {
        items.compactMap { dragPayload($0, missing: missing) }
    }

    static func dragPayload(_ item: HistoryItem, missing: Set<UUID>) -> Payload? {
        if let file = item.fileURL { return missing.contains(item.id) ? nil : .file(file) }
        if let text = item.text, !text.isEmpty { return .text(text) }
        return nil
    }

    enum Payload: Equatable {
        case file(URL)
        case text(String)

        var writer: any NSPasteboardWriting {
            switch self {
            case .file(let url): url as NSURL
            case .text(let text): text as NSString
            }
        }
    }

    /// Puts it on the pasteboard. Returns false when there was nothing to put.
    @MainActor
    @discardableResult
    func write(to pasteboard: NSPasteboard = .general) -> Bool {
        switch self {
        case .files(let urls):
            pasteboard.clearContents()
            return pasteboard.writeObjects(urls.map { $0 as NSURL })
        case .text(let text):
            pasteboard.clearContents()
            return pasteboard.setString(text, forType: .string)
        case .nothing:
            return false
        }
    }
}
