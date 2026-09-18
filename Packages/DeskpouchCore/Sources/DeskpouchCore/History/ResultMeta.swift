import Foundation

/// Extra facts about one capture, kept as JSON in the history row's `meta` column. Deliberately small and open
/// ended: a picked colour stores the exact sRGB it read (the row's text is only the format that was copied, and
/// hsl or oklch round on the way out), a screenshot stores the display and rect it came from so it can be
/// recaptured and compared (plan 04).
public struct ResultMeta: Codable, Sendable, Equatable {
    /// The exact colour behind a `color` row, `#rrggbb` in sRGB.
    public var srgb: String?
    /// Display the capture came from.
    public var display: UInt32?
    /// What was captured, in that display's points with a top-left origin: [x, y, width, height].
    public var rect: [Double]?

    public init(srgb: String? = nil, display: UInt32? = nil, rect: [Double]? = nil) {
        self.srgb = srgb
        self.display = display
        self.rect = rect
    }

    public var isEmpty: Bool { srgb == nil && display == nil && rect == nil }

    /// Nil when there is nothing worth storing, so empty metadata never writes a row of `{}`.
    public var json: String? {
        guard !isEmpty, let data = try? JSONEncoder().encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Nil for a row written before this column existed, or one holding something this build cannot read.
    public init?(json: String?) {
        guard let json, let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(ResultMeta.self, from: data) else { return nil }
        self = decoded
    }
}
