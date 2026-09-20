import Foundation

/// Turns dictated commands ("comma", "question mark", "new line") into the marks they name. English only.
/// The model punctuates around a command as if it were prose ("Hello. Comma. How are you"), so the punctuation
/// touching a command is dropped along with it.
///
/// Rules:
/// - A mark attaches to the previous word. A command that opens the text has nothing to attach to and is dropped.
/// - After a sentence end or a line break the next word is capitalised.
/// - A line break keeps a sentence end before it ("Done. New line" keeps the full stop) and drops a clause break.
/// - "period" and "dash" are also ordinary words, so they only count as commands when the model set
///   them apart: at the end of the text, or with punctuation of their own ("so, period." but not "a period of").
public struct SpokenPunctuation: Sendable {
    public static let `default` = SpokenPunctuation()

    /// Spoken form to written form. Longer phrases are matched first.
    static let commands: [(spoken: String, written: String)] = [
        ("new paragraph", "\n\n"),
        ("new line", "\n"),
        ("newline", "\n"),
        ("question mark", "?"),
        ("exclamation mark", "!"),
        ("exclamation point", "!"),
        ("full stop", "."),
        ("semicolon", ";"),
        ("semi colon", ";"),
        ("comma", ","),
        ("period", "."),
        ("colon", ":"),
        ("dash", " -"),
    ]

    static let ambiguous: Set<String> = ["period", "dash"]

    private let pattern: NSRegularExpression
    private let written: [String: String]

    public init() {
        let alternatives = Self.commands
            .map { NSRegularExpression.escapedPattern(for: $0.spoken).replacingOccurrences(of: " ", with: "\\s+") }
            .joined(separator: "|")
        // swiftlint:disable:next force_try
        pattern = try! NSRegularExpression(
            pattern: "([,.!?;:]*)\\s*(?<![\\p{L}\\p{N}'’-])(\(alternatives))(?![\\p{L}\\p{N}'’-])([,.!?;:]*)",
            options: [.caseInsensitive]
        )
        written = Dictionary(uniqueKeysWithValues: Self.commands.map { ($0.spoken, $0.written) })
    }

    public func apply(_ text: String) -> String {
        var text = text
        var searchFrom = text.startIndex
        while let match = pattern.firstMatch(in: text, range: NSRange(searchFrom..., in: text)),
              let range = Range(match.range, in: text),
              let commandRange = Range(match.range(at: 2), in: text) {
            let leading = Range(match.range(at: 1), in: text).map { String(text[$0]) } ?? ""
            let trailing = Range(match.range(at: 3), in: text).map { String(text[$0]) } ?? ""
            let spoken = text[commandRange].lowercased()
                .split(whereSeparator: \.isWhitespace).joined(separator: " ")
            let after = String(text[range.upperBound...]).trimmingLeadingWhitespace()

            if Self.ambiguous.contains(spoken), trailing.isEmpty, !after.isEmpty {
                // An ordinary word ("the best period of my life"): leave it and look further on.
                searchFrom = commandRange.upperBound
                continue
            }
            guard let mark = written[spoken] else {
                searchFrom = commandRange.upperBound
                continue
            }

            var before = String(text[..<range.lowerBound]).trimmingTrailingWhitespace()
            var rest = after
            let isBreak = mark.hasPrefix("\n")
            if isBreak {
                if let end = leading.last(where: Self.sentenceEnds.contains), !before.isEmpty,
                   before.last.map(Self.sentenceEnds.contains) != true {
                    before.append(end)
                }
                rest = rest.capitalisingFirst()
                text = before.isEmpty ? rest : before + mark + rest
            } else if before.isEmpty || before.hasSuffix("\n") {
                // Nothing to attach the mark to.
                text = before + rest.capitalisingFirst()
            } else {
                if let last = before.last, Self.marks.contains(last) { before.removeLast() }
                if mark.last.map(Self.sentenceEnds.contains) == true { rest = rest.capitalisingFirst() }
                text = before + mark + (rest.isEmpty ? "" : " " + rest)
            }
            searchFrom = text.index(text.startIndex, offsetBy: min(before.count, text.count))
        }
        return text.trimmingCharacters(in: .whitespaces)
    }

    private static let sentenceEnds: Set<Character> = [".", "!", "?"]
    private static let marks: Set<Character> = [",", ".", "!", "?", ";", ":"]
}

extension String {
    func trimmingTrailingWhitespace() -> String {
        String(reversed().drop(while: \.isWhitespace).reversed())
    }

    func trimmingLeadingWhitespace() -> String {
        String(drop(while: \.isWhitespace))
    }

    func capitalisingFirst() -> String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}
