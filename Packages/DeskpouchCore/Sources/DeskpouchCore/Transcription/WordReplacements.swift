import Foundation

/// One dictionary entry: what the engine tends to write, and what it should have written.
public struct WordReplacement: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var heard: String
    public var written: String

    public init(id: UUID = UUID(), heard: String, written: String) {
        self.id = id
        self.heard = heard
        self.written = written
    }

    /// An entry with nothing to look for does nothing; an empty `written` deletes the word.
    public var isUsable: Bool { !heard.trimmingCharacters(in: .whitespaces).isEmpty }
}

/// The user's dictionary: names and jargon the engine gets wrong ("desk pouch" to "Deskpouch"). Runs on the text
/// after decode, so it works the same on every engine. Whole words only, case-insensitive, any whitespace between
/// the words of a phrase. Longer entries win over shorter ones that overlap them.
public struct WordReplacements: Sendable {
    private let rules: [(pattern: NSRegularExpression, written: String)]

    public init(_ entries: [WordReplacement]) {
        rules = entries
            .filter(\.isUsable)
            .sorted { $0.heard.count > $1.heard.count }
            .compactMap { entry in
                let words = entry.heard.split(whereSeparator: \.isWhitespace)
                    .map { NSRegularExpression.escapedPattern(for: String($0)) }
                    .joined(separator: "\\s+")
                let pattern = "(?<![\\p{L}\\p{N}])\(words)(?![\\p{L}\\p{N}])"
                guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
                return (regex, entry.written.trimmingCharacters(in: .whitespaces))
            }
    }

    public var isEmpty: Bool { rules.isEmpty }

    public func apply(_ text: String) -> String {
        var text = text
        for rule in rules {
            let template = NSRegularExpression.escapedTemplate(for: rule.written)
            text = rule.pattern.stringByReplacingMatches(
                in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template
            )
        }
        return text
    }
}
