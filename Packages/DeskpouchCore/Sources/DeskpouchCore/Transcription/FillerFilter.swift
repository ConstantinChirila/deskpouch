import Foundation

/// Drops hesitation sounds ("um", "uh", "hmm") from a transcript and repairs the punctuation and capitalisation
/// the model attached to them. Parakeet cannot be told to skip fillers, so this runs on its text output.
///
/// Rules, applied left to right until no filler remains:
/// - The filler and its trailing punctuation go. A comma the model put before the filler goes too when the filler
///   carried its own comma ("I went, um, to" becomes "I went to").
/// - A sentence end on the filler moves to the previous word ("I think so, um." becomes "I think so.").
/// - The next word is capitalised when the filler opened a sentence ("Um, so I went" becomes "So I went").
public struct FillerFilter: Sendable {
    /// English sounds that are never words on their own. "oh", "like" and "you know" are left alone: they carry
    /// meaning. So are "er", "ah" and "mm", which are real text too ("the ER", "35 mm").
    public static let defaultFillers: [String] = [
        "um", "umm", "uhm", "uh", "uhh", "erm", "ehm", "hm", "hmm", "mhm",
    ]

    /// German hesitation sounds. "um" and "er" are words there.
    public static let germanFillers: [String] = ["äh", "ähm", "hm", "hmm"]

    /// The English filter.
    public static let `default` = FillerFilter()

    private static let german = FillerFilter(fillers: germanFillers)
    private static let none = FillerFilter(fillers: [])

    /// The filter for an ISO 639-1 language code. Languages without a list of their own get one that strips
    /// nothing: a sound that is a filler in one language is a word in another ("um" in German and Portuguese).
    public static func forLanguage(_ code: String?) -> FillerFilter {
        switch code?.lowercased().prefix(2) {
        case "en": .default
        case "de": german
        default: none
        }
    }

    /// Nil when there is nothing to strip.
    private let pattern: NSRegularExpression?

    /// - Parameter fillers: words to strip, matched case-insensitively on whole words. Apostrophes and hyphens
    ///   count as word characters, so "uh-oh" survives.
    public init(fillers: [String] = FillerFilter.defaultFillers) {
        guard !fillers.isEmpty else {
            pattern = nil
            return
        }
        let alternatives = fillers.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
        // swiftlint:disable:next force_try
        pattern = try! NSRegularExpression(
            pattern: "(?<![\\p{L}\\p{N}'’-])(?:\(alternatives))(?![\\p{L}\\p{N}'’-])([,.!?;:]*)",
            options: [.caseInsensitive]
        )
    }

    public func clean(_ text: String) -> String {
        guard let pattern else { return text }
        var text = text
        while let match = pattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range, in: text) {
            let trailing = Range(match.range(at: 1), in: text).map { String(text[$0]) } ?? ""
            var before = String(text[..<range.lowerBound])
            var after = String(text[range.upperBound...])
            before = before.trimmingTrailingWhitespace()
            after = after.trimmingLeadingWhitespace()

            let sentenceStart = before.isEmpty || before.last.map(Self.sentenceEnds.contains) == true
            if let end = trailing.first(where: Self.sentenceEnds.contains) {
                if !sentenceStart {
                    if let last = before.last, Self.clauseBreaks.contains(last) {
                        before.removeLast()
                    }
                    if before.last.map(Self.sentenceEnds.contains) != true {
                        before.append(end)
                    }
                }
            } else if trailing.contains(","), let last = before.last, Self.clauseBreaks.contains(last) {
                before.removeLast()
            }
            if sentenceStart, let first = after.first {
                after = first.uppercased() + after.dropFirst()
            }
            let joiner = before.isEmpty || after.isEmpty ? "" : " "
            text = before + joiner + after
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let sentenceEnds: Set<Character> = [".", "!", "?"]
    private static let clauseBreaks: Set<Character> = [",", ";", ":"]
}
