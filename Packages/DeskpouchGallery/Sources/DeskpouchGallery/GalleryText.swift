import DeskpouchCore
import Foundation
import SwiftUI

/// The words on a tile and under the preview.
enum GalleryText {
    /// File name for a capture, the text itself for a transcript or a colour.
    static func title(_ item: HistoryItem) -> String {
        if let text = item.text {
            return text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        }
        return item.fileURL?.lastPathComponent ?? "Untitled"
    }

    /// "10:41 · 0:12 · pasted into Notes".
    static func meta(_ item: HistoryItem) -> String {
        var parts = [DayGroup.clock(item.createdAt)]
        if let duration = item.duration, item.text == nil {
            parts.append(TimeFormat.minutesSeconds(duration))
        }
        if let target = item.pastedInto {
            parts.append("pasted into \(target)")
        }
        return parts.joined(separator: " · ")
    }

    static func kindLabel(_ kind: HistoryKind) -> String {
        switch kind {
        case .screenshot: "Screenshots"
        case .recording: "Recordings"
        case .text: "Text"
        case .color: "Colours"
        case .meeting: "Meetings"
        case .convert: "Converted"
        }
    }

    /// "1 word", "248 words".
    static func wordCount(_ text: String) -> String {
        let count = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
        return count == 1 ? "1 word" : "\(count) words"
    }

    /// `#rrggbb` to a colour; nil for anything else.
    static func color(hex: String?) -> Color? {
        guard let hex, hex.hasPrefix("#"), hex.count == 7, let value = UInt32(hex.dropFirst(), radix: 16) else { return nil }
        return Color(hex: value)
    }
}
