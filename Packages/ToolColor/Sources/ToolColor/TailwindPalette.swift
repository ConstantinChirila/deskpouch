import Foundation

/// Tailwind v4's default palette, for the loupe's hint. Compared in CIE Lab with ΔE2000; many v4 entries sit
/// outside sRGB, so they are compared unclamped and a picked colour rarely matches one exactly.
public enum TailwindPalette {
    public struct Match: Equatable, Sendable {
        /// `amber-500`, `white`.
        public let name: String
        public let deltaE: Double

        /// Close enough that the colour is that entry for practical purposes.
        public var isExact: Bool { deltaE < 1 }
    }

    /// Past this the loupe says "custom" instead of naming an entry.
    public static let hintThreshold = 6.0

    struct Entry: Sendable {
        let name: String
        let lab: LabColor
    }

    static let entries: [Entry] = {
        var list = oklchEntries.map { entry in
            Entry(name: entry.name, lab: SRGBColor(oklchLightness: entry.l, chroma: entry.c, hue: entry.h).lab)
        }
        list.append(Entry(name: "black", lab: SRGBColor(hex: 0x000000).lab))
        list.append(Entry(name: "white", lab: SRGBColor(hex: 0xFFFFFF).lab))
        return list
    }()

    /// The closest entry, or nil when even that one is `hintThreshold` or further away.
    public static func nearest(to color: SRGBColor) -> Match? {
        let lab = color.clamped.lab
        var best: Match?
        for entry in entries {
            let distance = lab.deltaE2000(entry.lab)
            if distance < (best?.deltaE ?? .infinity) {
                best = Match(name: entry.name, deltaE: distance)
            }
        }
        guard let best, best.deltaE < hintThreshold else { return nil }
        return best
    }
}
