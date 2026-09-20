import Foundation

/// Writes spelled-out numbers as digits. English only. Parakeet already does this for most numbers ("25%",
/// "January 5th, 2025", "1,200"); this catches what it leaves as words, mostly money, times and long cardinals.
///
/// Rules:
/// - A run of number words becomes digits when it is worth 10 or more, or takes more than one word.
///   "one idea and two problems" stays: a lone word under ten is prose, and "one" is often a pronoun.
/// - A lone word under ten does convert where a unit makes it a figure: "five dollars" is "$5", "three pm" is
///   "3 PM", "five percent" is "5%", "two point five" is "2.5".
/// - "two hundred thirty two dollars and fifty cents" is "$232.50"; euros work the same. Pounds are left alone,
///   they are also a weight.
/// - "three thirty pm" is "3:30 PM".
/// - Two runs of two digits in a row are a year: "nineteen ninety nine" is "1999".
/// - Ordinals follow the same size rule ("twenty first" is "21st", "first" stays). "twenty second" only converts
///   next to "the" or "of", since "a twenty second delay" is a duration.
/// - Words only join a run across spaces or a hyphen, never across punctuation.
public struct SpokenNumbers: Sendable {
    public static let `default` = SpokenNumbers()

    public init() {}

    public func apply(_ text: String) -> String {
        var pieces = Self.split(text)
        let words = pieces.indices.filter { pieces[$0].isWord }
        var position = 0
        while position < words.count {
            guard let number = parseNumber(pieces, words, at: position) else {
                position += 1
                continue
            }
            var end = number.end
            var written: String?

            if let decimal = parseDecimal(pieces, words, after: end) {
                end = decimal.end
                let percent = word(pieces, words, end + 1) == "percent" && joins(pieces, words, end)
                written = "\(number.value).\(decimal.digits)" + (percent ? "%" : "")
                if percent { end += 1 }
            } else if number.ordinal {
                if number.value >= 10 || number.wordCount > 1, ordinalAllowed(pieces, words, number, start: position) {
                    written = "\(number.value)\(Self.ordinalSuffix(number.value))"
                }
            } else if let next = word(pieces, words, end + 1), joins(pieces, words, end) {
                if next == "percent" {
                    written = "\(Self.grouped(number.value))%"
                    end += 1
                } else if let symbol = Self.currencies[next] {
                    (written, end) = money(pieces, words, number: number, symbol: symbol, unitAt: end + 1)
                } else if let time = parseTime(pieces, words, hour: number, after: end) {
                    written = time.text
                    end = time.end
                } else if let year = parseYear(pieces, words, first: number, after: end) {
                    written = year.text
                    end = year.end
                }
            }
            if written == nil, !number.ordinal, number.value >= 10 || number.wordCount > 1 {
                written = Self.plain(number)
            }

            guard let written else {
                position = number.end + 1
                continue
            }
            // Collapse the run into its first piece; the pieces in between (spaces, hyphens, words) go.
            pieces[words[position]].text = written
            if end > position {
                for index in (words[position] + 1)...words[end] { pieces[index].text = "" }
            }
            position = end + 1
        }
        return pieces.map(\.text).joined()
    }

    // MARK: Pieces

    struct Piece {
        var text: String
        let isWord: Bool
    }

    /// Alternating words and whatever sits between them, so the text can be put back together untouched.
    static func split(_ text: String) -> [Piece] {
        var pieces: [Piece] = []
        var current = ""
        var inWord = false
        for character in text {
            let isWordCharacter = character.isLetter || character == "'" || character == "’"
            if isWordCharacter != inWord, !current.isEmpty {
                pieces.append(Piece(text: current, isWord: inWord))
                current = ""
            }
            inWord = isWordCharacter
            current.append(character)
        }
        if !current.isEmpty { pieces.append(Piece(text: current, isWord: inWord)) }
        return pieces
    }

    private func word(_ pieces: [Piece], _ words: [Int], _ position: Int) -> String? {
        guard words.indices.contains(position) else { return nil }
        return pieces[words[position]].text.lowercased().replacingOccurrences(of: "’", with: "'")
    }

    /// True when only spaces or a hyphen separate the word at `position` from the next one.
    private func joins(_ pieces: [Piece], _ words: [Int], _ position: Int) -> Bool {
        guard words.indices.contains(position + 1) else { return false }
        let between = pieces[(words[position] + 1)..<words[position + 1]].map(\.text).joined()
        return between.allSatisfy { $0 == " " || $0 == "-" } && !between.isEmpty
    }

    // MARK: Cardinals and ordinals

    struct Number {
        var value: Int
        /// Position (in `words`) of the last word of the run.
        var end: Int
        var wordCount: Int
        var ordinal = false
        /// The run ended on a scale word with nothing after it ("three million").
        var roundScale: (count: Int, name: String)?
    }

    private func parseNumber(_ pieces: [Piece], _ words: [Int], at start: Int) -> Number? {
        var total = 0
        var current = 0
        var position = start
        var count = 0
        var lastKind: Kind?
        var ordinal = false
        var roundScale: (Int, String)?

        while let text = word(pieces, words, position) {
            if position > start, !joins(pieces, words, position - 1) { break }
            if let small = Self.units[text] ?? Self.ordinalUnits[text] {
                guard lastKind == nil || lastKind == .tens || lastKind == .hundred || lastKind == .scale else { break }
                if lastKind == .tens, small >= 10 { break }
                current += small
                lastKind = .unit
                ordinal = Self.ordinalUnits[text] != nil
                roundScale = nil
            } else if let tens = Self.tens[text] ?? Self.ordinalTens[text] {
                guard lastKind == nil || lastKind == .hundred || lastKind == .scale else { break }
                current += tens
                lastKind = .tens
                ordinal = Self.ordinalTens[text] != nil
                roundScale = nil
            } else if text == "hundred" || text == "hundredth" {
                guard lastKind == .unit, current > 0, current < 100 else { break }
                current *= 100
                lastKind = .hundred
                ordinal = text == "hundredth"
                roundScale = nil
            } else if let scale = Self.scales[text] {
                guard lastKind != nil, lastKind != .scale, current > 0 else { break }
                roundScale = total == 0 ? (current, text) : nil
                total += current * scale
                current = 0
                lastKind = .scale
            } else if text == "and" {
                // "two hundred and five": only inside a run, and only when a number follows.
                guard lastKind == .hundred || lastKind == .scale,
                      joins(pieces, words, position),
                      let next = word(pieces, words, position + 1),
                      Self.units[next] != nil || Self.tens[next] != nil
                        || Self.ordinalUnits[next] != nil || Self.ordinalTens[next] != nil else { break }
                position += 1
                continue
            } else {
                break
            }
            count += 1
            position += 1
            if ordinal { break }
        }
        guard count > 0 else { return nil }
        // Step back over an "and" that was skipped but led nowhere (cannot happen with the lookahead; defensive).
        var end = position - 1
        while end > start, word(pieces, words, end) == "and" { end -= 1 }
        return Number(
            value: total + current, end: end, wordCount: count, ordinal: ordinal,
            roundScale: roundScale.map { (count: $0.0, name: $0.1) }
        )
    }

    private enum Kind { case unit, tens, hundred, scale }

    private func ordinalAllowed(_ pieces: [Piece], _ words: [Int], _ number: Number, start: Int) -> Bool {
        guard word(pieces, words, number.end) == "second" else { return true }
        return word(pieces, words, start - 1) == "the" || word(pieces, words, number.end + 1) == "of"
    }

    // MARK: Decimals, money, time, years

    private func parseDecimal(_ pieces: [Piece], _ words: [Int], after end: Int) -> (digits: String, end: Int)? {
        guard word(pieces, words, end + 1) == "point", joins(pieces, words, end) else { return nil }
        var digits = ""
        var position = end + 2
        while let text = word(pieces, words, position), joins(pieces, words, position - 1),
              let digit = text == "oh" ? 0 : Self.units[text], digit < 10 {
            digits += String(digit)
            position += 1
        }
        return digits.isEmpty ? nil : (digits, position - 1)
    }

    private func money(
        _ pieces: [Piece], _ words: [Int], number: Number, symbol: String, unitAt: Int
    ) -> (String?, Int) {
        var end = unitAt
        var cents: Int?
        // "... dollars and fifty cents" or "... dollars fifty cents"
        var next = unitAt + 1
        if word(pieces, words, next) == "and", joins(pieces, words, unitAt) { next += 1 }
        if next > unitAt, joins(pieces, words, next - 1),
           let minor = parseNumber(pieces, words, at: next), !minor.ordinal, minor.value < 100,
           let unit = word(pieces, words, minor.end + 1), unit == "cents" || unit == "cent",
           joins(pieces, words, minor.end) {
            cents = minor.value
            end = minor.end + 1
        }
        let amount = Self.grouped(number.value)
        return (cents.map { "\(symbol)\(amount).\(String(format: "%02d", $0))" } ?? "\(symbol)\(amount)", end)
    }

    private func parseTime(
        _ pieces: [Piece], _ words: [Int], hour: Number, after end: Int
    ) -> (text: String, end: Int)? {
        guard (1...12).contains(hour.value) else { return nil }
        var position = end + 1
        var minutes: Int?
        if word(pieces, words, position) == "oh", joins(pieces, words, position),
           let digit = word(pieces, words, position + 1).flatMap({ Self.units[$0] }), digit < 10 {
            minutes = digit
            position += 2
        } else if let run = parseNumber(pieces, words, at: position), !run.ordinal, (10...59).contains(run.value) {
            minutes = run.value
            position = run.end + 1
        }
        guard let meridiem = word(pieces, words, position), meridiem == "am" || meridiem == "pm",
              joins(pieces, words, position - 1) else { return nil }
        let clock = minutes.map { "\(hour.value):\(String(format: "%02d", $0))" } ?? "\(hour.value)"
        return ("\(clock) \(meridiem.uppercased())", position)
    }

    private func parseYear(
        _ pieces: [Piece], _ words: [Int], first: Number, after end: Int
    ) -> (text: String, end: Int)? {
        guard (10...99).contains(first.value), first.roundScale == nil,
              let second = parseNumber(pieces, words, at: end + 1), !second.ordinal,
              (10...99).contains(second.value), second.roundScale == nil else { return nil }
        return ("\(first.value)\(second.value)", second.end)
    }

    // MARK: Formatting

    private static func plain(_ number: Number) -> String {
        if let round = number.roundScale, round.name != "thousand" { return "\(round.count) \(round.name)" }
        return grouped(number.value)
    }

    /// "1,200", as Parakeet writes its own.
    static func grouped(_ value: Int) -> String {
        guard value >= 1000 else { return String(value) }
        var digits = String(value)
        var out = ""
        while digits.count > 3 {
            out = "," + digits.suffix(3) + out
            digits.removeLast(3)
        }
        return digits + out
    }

    static func ordinalSuffix(_ value: Int) -> String {
        if (11...13).contains(value % 100) { return "th" }
        switch value % 10 {
        case 1: return "st"
        case 2: return "nd"
        case 3: return "rd"
        default: return "th"
        }
    }

    // MARK: Vocabulary

    static let units: [String: Int] = [
        "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8,
        "nine": 9, "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15,
        "sixteen": 16, "seventeen": 17, "eighteen": 18, "nineteen": 19,
    ]
    static let tens: [String: Int] = [
        "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90,
    ]
    static let ordinalUnits: [String: Int] = [
        "first": 1, "second": 2, "third": 3, "fourth": 4, "fifth": 5, "sixth": 6, "seventh": 7, "eighth": 8,
        "ninth": 9, "tenth": 10, "eleventh": 11, "twelfth": 12, "thirteenth": 13, "fourteenth": 14,
        "fifteenth": 15, "sixteenth": 16, "seventeenth": 17, "eighteenth": 18, "nineteenth": 19,
    ]
    static let ordinalTens: [String: Int] = [
        "twentieth": 20, "thirtieth": 30, "fortieth": 40, "fiftieth": 50, "sixtieth": 60, "seventieth": 70,
        "eightieth": 80, "ninetieth": 90,
    ]
    static let scales: [String: Int] = ["thousand": 1_000, "million": 1_000_000, "billion": 1_000_000_000]
    static let currencies: [String: String] = ["dollars": "$", "dollar": "$", "euros": "€", "euro": "€"]
}
