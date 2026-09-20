import Foundation

/// Finds a closing "send": the dictation is pasted without it and Return is pressed afterwards.
///
/// Only a "send" the model set apart as its own sentence counts ("See you at five. Send."), or one that is the
/// whole dictation. "Then press send." is prose and stays.
public enum SpokenSend {
    public struct Parsed: Sendable, Equatable {
        public let text: String
        public let submit: Bool

        public init(text: String, submit: Bool) {
            self.text = text
            self.submit = submit
        }
    }

    public static func parse(_ text: String) -> Parsed {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let match = pattern.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
              let range = Range(match.range, in: trimmed) else {
            return Parsed(text: text, submit: false)
        }
        let body = String(trimmed[..<range.lowerBound])
        return Parsed(text: body.trimmingTrailingWhitespace(), submit: true)
    }

    // The lookbehind keeps the sentence end before "send" in the body.
    // swiftlint:disable:next force_try
    private static let pattern = try! NSRegularExpression(
        pattern: "(?:^|(?<=[.!?…])\\s+)send[.!?]*$",
        options: [.caseInsensitive]
    )
}
