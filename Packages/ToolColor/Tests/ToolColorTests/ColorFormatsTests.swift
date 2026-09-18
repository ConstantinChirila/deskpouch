import Foundation
import Testing
@testable import ToolColor

/// Reference values from culori 4 (`oklch`, `lab65`, `hsl` converters and `differenceCiede2000`).
struct ColorFormatsTests {
    struct Reference: Sendable, CustomTestStringConvertible {
        let hex: UInt32
        let oklch: (Double, Double, Double)
        let lab: (Double, Double, Double)
        let hsl: (Double, Double, Double)
        var testDescription: String { String(format: "#%06x", hex) }
    }

    static let references: [Reference] = [
        Reference(hex: 0xF59E0B, oklch: (0.7686, 0.1647, 70.08), lab: (72.157, 23.487, 75.228), hsl: (37.69, 0.9213, 0.5020)),
        Reference(hex: 0x000000, oklch: (0, 0, 0), lab: (0, 0, 0), hsl: (0, 0, 0)),
        Reference(hex: 0xFFFFFF, oklch: (1, 0, 0), lab: (100, 0, 0), hsl: (0, 0, 1)),
        Reference(hex: 0x2DD4A3, oklch: (0.7767, 0.1489, 167.47), lab: (76.245, -52.566, 12.647), hsl: (162.40, 0.6601, 0.5039)),
        Reference(hex: 0x6366F1, oklch: (0.5854, 0.2041, 277.12), lab: (50.104, 38.696, -70.484), hsl: (238.73, 0.8353, 0.6667)),
        Reference(hex: 0xFF0000, oklch: (0.6280, 0.2577, 29.23), lab: (53.237, 80.090, 67.203), hsl: (0, 1, 0.5)),
    ]

    @Test(arguments: references)
    func conversionsMatchReference(_ ref: Reference) {
        let color = SRGBColor(hex: ref.hex)
        let oklch = color.oklch
        #expect(abs(oklch.lightness - ref.oklch.0) < 0.0005)
        #expect(abs(oklch.chroma - ref.oklch.1) < 0.0005)
        #expect(abs(oklch.hue - ref.oklch.2) < 0.05)
        let lab = color.lab
        #expect(abs(lab.l - ref.lab.0) < 0.02)
        #expect(abs(lab.a - ref.lab.1) < 0.05)
        #expect(abs(lab.b - ref.lab.2) < 0.05)
        let hsl = color.hsl
        #expect(abs(hsl.hue - ref.hsl.0) < 0.01)
        #expect(abs(hsl.saturation - ref.hsl.1) < 0.0001)
        #expect(abs(hsl.lightness - ref.hsl.2) < 0.0001)
    }

    @Test(arguments: references)
    func everyFormatParsesBackToTheSameBytes(_ ref: Reference) throws {
        let color = SRGBColor(hex: ref.hex)
        for format in ColorFormat.allCases {
            let parsed = try #require(ColorFormat.parse(format.string(for: color)), "\(format)")
            // hsl and oklch are rounded for display, so they can land one step off.
            let tolerance: Int = format == .hsl || format == .oklch ? 3 : 0
            let a = parsed.bytes, b = color.bytes
            #expect(abs(Int(a.red) - Int(b.red)) <= tolerance, "\(format)")
            #expect(abs(Int(a.green) - Int(b.green)) <= tolerance, "\(format)")
            #expect(abs(Int(a.blue) - Int(b.blue)) <= tolerance, "\(format)")
        }
    }

    @Test func formatStrings() {
        let amber = SRGBColor(hex: 0xF59E0B)
        #expect(ColorFormat.hex.string(for: amber) == "#f59e0b")
        #expect(ColorFormat.rgb.string(for: amber) == "rgb(245 158 11)")
        #expect(ColorFormat.hsl.string(for: amber) == "hsl(38 92% 50%)")
        #expect(ColorFormat.oklch.string(for: amber) == "oklch(0.769 0.165 70.1)")
        #expect(ColorFormat.swiftUI.string(for: amber) == "Color(red: 0.961, green: 0.620, blue: 0.043)")
        #expect(ColorFormat.oklch.string(for: SRGBColor(hex: 0xFFFFFF)) == "oklch(1 0 0)")
        #expect(ColorFormat.hsl.string(for: SRGBColor(hex: 0x808080)) == "hsl(0 0% 50%)")
    }

    @Test func parseAcceptsVariantsAndRejectsJunk() {
        #expect(ColorFormat.parse("#FFF") == SRGBColor(hex: 0xFFFFFF))
        #expect(ColorFormat.parse("  #f59e0b\n") == SRGBColor(hex: 0xF59E0B))
        #expect(ColorFormat.parse("rgb(245, 158, 11)") == SRGBColor(hex: 0xF59E0B))
        #expect(ColorFormat.parse("Can we move standup to ten") == nil)
        #expect(ColorFormat.parse("#12345") == nil)
        #expect(ColorFormat.parse("rgb(1 2)") == nil)
        #expect(ColorFormat.parse("lab(50 20 30)") == nil)
    }

    @Test func oklchRoundTripKeepsWideGamutUnclamped() {
        // Tailwind v4 amber-500 is outside sRGB: blue goes negative before clamping (culori: -0.2175).
        let amber500 = SRGBColor(oklchLightness: 0.769, chroma: 0.188, hue: 70.08)
        #expect(abs(amber500.red - 0.9943) < 0.001)
        #expect(abs(amber500.green - 0.6021) < 0.001)
        #expect(abs(amber500.blue - -0.2175) < 0.001)
        #expect(amber500.hex == "#fe9a00")
    }

    @Test func deltaE2000MatchesSharmaTable() {
        let a = LabColor(l: 50, a: 2.6772, b: -79.7751)
        let b = LabColor(l: 50, a: 0, b: -82.7485)
        #expect(abs(a.deltaE2000(b) - 2.0425) < 0.0001)
        #expect(abs(LabColor(l: 50, a: -1.3802, b: -84.2814).deltaE2000(b) - 1.0000) < 0.0001)
        #expect(a.deltaE2000(a) == 0)
    }
}

struct TailwindPaletteTests {
    @Test func tableHasTheFullPalette() {
        #expect(TailwindPalette.oklchEntries.count == 26 * 11)
        #expect(TailwindPalette.entries.count == 26 * 11 + 2)
        #expect(Set(TailwindPalette.entries.map(\.name)).count == TailwindPalette.entries.count)
    }

    /// Expected names and distances from culori over the same table.
    @Test(arguments: [
        (0xF59E0B as UInt32, "amber-500", 4.822),
        (0x3B82F6, "blue-500", 1.652),
        (0x2DD4A3, "emerald-400", 3.888),
        (0x123456, "sky-950", 3.544),
        (0x2B7FFF, "blue-500", 0.735),
        (0x71717B, "zinc-500", 0.212),
        (0xFFFFFF, "white", 0),
    ])
    func nearestEntry(hex: UInt32, name: String, deltaE: Double) throws {
        let match = try #require(TailwindPalette.nearest(to: SRGBColor(hex: hex)))
        #expect(match.name == name)
        #expect(abs(match.deltaE - deltaE) < 0.02)
    }

    @Test func exactOnlyUnderOne() throws {
        #expect(try #require(TailwindPalette.nearest(to: SRGBColor(hex: 0x71717B))).isExact)
        #expect(try !#require(TailwindPalette.nearest(to: SRGBColor(hex: 0xF59E0B))).isExact)
    }

    @Test func farColoursHaveNoHint() {
        // culori: #00ff00 is 11.1 from lime-400, #00ffff 8.4 from cyan-300.
        #expect(TailwindPalette.nearest(to: SRGBColor(hex: 0x00FF00)) == nil)
        #expect(TailwindPalette.nearest(to: SRGBColor(hex: 0x00FFFF)) == nil)
    }
}
