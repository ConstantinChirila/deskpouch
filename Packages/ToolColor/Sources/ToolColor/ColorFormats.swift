import Foundation

/// An sRGB colour, gamma encoded, components in 0...1. Values outside that range only appear as the unclamped
/// result of converting a wide-gamut OKLCH colour (the Tailwind v4 palette); `clamped` brings them back.
public struct SRGBColor: Equatable, Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public init(hex: UInt32) {
        self.init(bytes: UInt8((hex >> 16) & 0xFF), UInt8((hex >> 8) & 0xFF), UInt8(hex & 0xFF))
    }

    public init(bytes red: UInt8, _ green: UInt8, _ blue: UInt8) {
        self.init(red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255)
    }

    public var clamped: SRGBColor {
        SRGBColor(red: red.clamped01, green: green.clamped01, blue: blue.clamped01)
    }

    /// 8-bit channels, rounded.
    public var bytes: (red: UInt8, green: UInt8, blue: UInt8) {
        (Self.byte(red), Self.byte(green), Self.byte(blue))
    }

    /// Lowercase `#rrggbb`.
    public var hex: String {
        let b = bytes
        return String(format: "#%02x%02x%02x", b.red, b.green, b.blue)
    }

    private static func byte(_ value: Double) -> UInt8 {
        UInt8((value.clamped01 * 255).rounded())
    }
}

// MARK: Spaces

extension SRGBColor {
    /// Hue in degrees (0 for greys), saturation and lightness in 0...1.
    public var hsl: (hue: Double, saturation: Double, lightness: Double) {
        let c = clamped
        let maxValue = max(c.red, c.green, c.blue)
        let minValue = min(c.red, c.green, c.blue)
        let lightness = (maxValue + minValue) / 2
        let delta = maxValue - minValue
        guard delta > 0 else { return (0, 0, lightness) }
        let saturation = delta / (1 - abs(2 * lightness - 1))
        var hue: Double
        switch maxValue {
        case c.red: hue = ((c.green - c.blue) / delta).truncatingRemainder(dividingBy: 6)
        case c.green: hue = (c.blue - c.red) / delta + 2
        default: hue = (c.red - c.green) / delta + 4
        }
        hue *= 60
        if hue < 0 { hue += 360 }
        return (hue, saturation, lightness)
    }

    public init(hue: Double, saturation: Double, lightness: Double) {
        let chroma = (1 - abs(2 * lightness - 1)) * saturation
        let sector = (hue.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) / 60
        let x = chroma * (1 - abs(sector.truncatingRemainder(dividingBy: 2) - 1))
        let (r, g, b): (Double, Double, Double) = switch sector {
        case ..<1: (chroma, x, 0)
        case ..<2: (x, chroma, 0)
        case ..<3: (0, chroma, x)
        case ..<4: (0, x, chroma)
        case ..<5: (x, 0, chroma)
        default: (chroma, 0, x)
        }
        let m = lightness - chroma / 2
        self.init(red: r + m, green: g + m, blue: b + m)
    }

    /// Linear-light sRGB. Sign preserving, so unclamped wide-gamut values survive the round trip.
    var linear: (Double, Double, Double) {
        (Self.toLinear(red), Self.toLinear(green), Self.toLinear(blue))
    }

    init(linear r: Double, _ g: Double, _ b: Double) {
        self.init(red: Self.fromLinear(r), green: Self.fromLinear(g), blue: Self.fromLinear(b))
    }

    private static func toLinear(_ value: Double) -> Double {
        let magnitude = abs(value)
        let result = magnitude <= 0.04045 ? magnitude / 12.92 : pow((magnitude + 0.055) / 1.055, 2.4)
        return value < 0 ? -result : result
    }

    private static func fromLinear(_ value: Double) -> Double {
        let magnitude = abs(value)
        let result = magnitude <= 0.0031308 ? magnitude * 12.92 : 1.055 * pow(magnitude, 1 / 2.4) - 0.055
        return value < 0 ? -result : result
    }

    /// OKLCH (Björn Ottosson's OKLab in polar form): lightness 0...1, chroma, hue in degrees (0 when achromatic).
    public var oklch: (lightness: Double, chroma: Double, hue: Double) {
        let (r, g, b) = linear
        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        let lightness = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
        let a = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
        let bb = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
        let chroma = (a * a + bb * bb).squareRoot()
        guard chroma > 1e-4 else { return (lightness, 0, 0) }
        var hue = atan2(bb, a) * 180 / .pi
        if hue < 0 { hue += 360 }
        return (lightness, chroma, hue)
    }

    /// Unclamped: a wide-gamut colour comes back with components outside 0...1.
    public init(oklchLightness lightness: Double, chroma: Double, hue: Double) {
        let radians = hue * .pi / 180
        let a = chroma * cos(radians)
        let b = chroma * sin(radians)
        let l = pow(lightness + 0.3963377774 * a + 0.2158037573 * b, 3)
        let m = pow(lightness - 0.1055613458 * a - 0.0638541728 * b, 3)
        let s = pow(lightness - 0.0894841775 * a - 1.2914855480 * b, 3)
        self.init(
            linear: 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
            -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
            -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
        )
    }

    /// CIE L*a*b* under D65, for ΔE2000.
    var lab: LabColor {
        let (r, g, b) = linear
        let x = (0.4124564 * r + 0.3575761 * g + 0.1804375 * b) / 0.95047
        let y = 0.2126729 * r + 0.7151522 * g + 0.0721750 * b
        let z = (0.0193339 * r + 0.1191920 * g + 0.9503041 * b) / 1.08883
        func f(_ t: Double) -> Double {
            t > 216.0 / 24389 ? cbrt(t) : (24389.0 / 27 * t + 16) / 116
        }
        let fx = f(x), fy = f(y), fz = f(z)
        return LabColor(l: 116 * fy - 16, a: 500 * (fx - fy), b: 200 * (fy - fz))
    }
}

struct LabColor: Equatable, Sendable {
    var l: Double
    var a: Double
    var b: Double

    /// CIEDE2000 colour difference (Sharma, Wu, Dalal 2005), kL = kC = kH = 1.
    func deltaE2000(_ other: LabColor) -> Double {
        let deg = Double.pi / 180
        let c1 = (a * a + b * b).squareRoot()
        let c2 = (other.a * other.a + other.b * other.b).squareRoot()
        let cMean = (c1 + c2) / 2
        let c7 = pow(cMean, 7)
        let g = 0.5 * (1 - (c7 / (c7 + pow(25, 7))).squareRoot())
        let a1 = (1 + g) * a
        let a2 = (1 + g) * other.a
        let cp1 = (a1 * a1 + b * b).squareRoot()
        let cp2 = (a2 * a2 + other.b * other.b).squareRoot()
        func hue(_ x: Double, _ y: Double) -> Double {
            guard x != 0 || y != 0 else { return 0 }
            let h = atan2(y, x) / deg
            return h < 0 ? h + 360 : h
        }
        let hp1 = hue(a1, b)
        let hp2 = hue(a2, other.b)

        let dL = other.l - l
        let dC = cp2 - cp1
        var dh = 0.0
        if cp1 * cp2 != 0 {
            dh = hp2 - hp1
            if dh > 180 { dh -= 360 } else if dh < -180 { dh += 360 }
        }
        let dH = 2 * (cp1 * cp2).squareRoot() * sin(dh / 2 * deg)

        let lMean = (l + other.l) / 2
        let cpMean = (cp1 + cp2) / 2
        var hMean = hp1 + hp2
        if cp1 * cp2 != 0 {
            if abs(hp1 - hp2) > 180 {
                hMean = hp1 + hp2 < 360 ? (hp1 + hp2 + 360) / 2 : (hp1 + hp2 - 360) / 2
            } else {
                hMean = (hp1 + hp2) / 2
            }
        }
        let t = 1 - 0.17 * cos((hMean - 30) * deg) + 0.24 * cos(2 * hMean * deg)
            + 0.32 * cos((3 * hMean + 6) * deg) - 0.20 * cos((4 * hMean - 63) * deg)
        let dTheta = 30 * exp(-pow((hMean - 275) / 25, 2))
        let cp7 = pow(cpMean, 7)
        let rc = 2 * (cp7 / (cp7 + pow(25, 7))).squareRoot()
        let lShift = pow(lMean - 50, 2)
        let sl = 1 + 0.015 * lShift / (20 + lShift).squareRoot()
        let sc = 1 + 0.045 * cpMean
        let sh = 1 + 0.015 * cpMean * t
        let rt = -sin(2 * dTheta * deg) * rc
        let tl = dL / sl, tc = dC / sc, th = dH / sh
        return (tl * tl + tc * tc + th * th + rt * tc * th).squareRoot()
    }
}

// MARK: Formats

/// What a click copies. Stored under `color.format`.
public enum ColorFormat: String, CaseIterable, Codable, Sendable, Identifiable {
    case hex, rgb, hsl, oklch, swiftUI

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .hex: "Hex"
        case .rgb: "RGB"
        case .hsl: "HSL"
        case .oklch: "OKLCH"
        case .swiftUI: "SwiftUI"
        }
    }

    /// `#f59e0b`, `rgb(245 158 11)`, `hsl(38 92% 50%)`, `oklch(0.769 0.165 70.1)`,
    /// `Color(red: 0.961, green: 0.620, blue: 0.043)`.
    public func string(for color: SRGBColor) -> String {
        let color = color.clamped
        switch self {
        case .hex:
            return color.hex
        case .rgb:
            let b = color.bytes
            return "rgb(\(b.red) \(b.green) \(b.blue))"
        case .hsl:
            let hsl = color.hsl
            return "hsl(\(Int(hsl.hue.rounded()) % 360) \(Int((hsl.saturation * 100).rounded()))% \(Int((hsl.lightness * 100).rounded()))%)"
        case .oklch:
            let o = color.oklch
            return "oklch(\(Self.trimmed(o.lightness, 3)) \(Self.trimmed(o.chroma, 3)) \(Self.trimmed(o.hue.rounded(toPlaces: 1).truncatingRemainder(dividingBy: 360), 1)))"
        case .swiftUI:
            // Rounded from the 8-bit value, so the copy matches the hex shown next to it.
            let b = color.bytes
            func channel(_ byte: UInt8) -> String { String(format: "%.3f", Double(byte) / 255) }
            return "Color(red: \(channel(b.red)), green: \(channel(b.green)), blue: \(channel(b.blue)))"
        }
    }

    /// Reads back any of the strings above (the History swatch), plus 3-digit hex. Nil for anything else.
    public static func parse(_ string: String) -> SRGBColor? {
        let text = string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if text.hasPrefix("#") {
            var digits = String(text.dropFirst())
            if digits.count == 3 { digits = digits.map { "\($0)\($0)" }.joined() }
            guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
            return SRGBColor(hex: value)
        }
        guard let open = text.firstIndex(of: "("), text.hasSuffix(")") else { return nil }
        let name = text[..<open]
        let body = text[text.index(after: open)..<text.index(before: text.endIndex)]
        let tokens = body
            .replacingOccurrences(of: ",", with: " ")
            .split(separator: " ")
            .map { $0.replacingOccurrences(of: "red:", with: "").replacingOccurrences(of: "green:", with: "").replacingOccurrences(of: "blue:", with: "") }
            .filter { !$0.isEmpty }
        func number(_ token: String) -> Double? {
            token.hasSuffix("%") ? Double(token.dropLast()).map { $0 / 100 } : Double(token)
        }
        let values = tokens.compactMap(number)
        guard values.count == 3, tokens.count == 3 else { return nil }
        switch name {
        case "rgb":
            return SRGBColor(red: values[0] / 255, green: values[1] / 255, blue: values[2] / 255)
        case "hsl":
            return SRGBColor(hue: values[0], saturation: values[1], lightness: values[2])
        case "oklch":
            return SRGBColor(oklchLightness: values[0], chroma: values[1], hue: values[2]).clamped
        case "color":
            return SRGBColor(red: values[0], green: values[1], blue: values[2])
        default:
            return nil
        }
    }

    /// Fixed decimals with trailing zeros dropped: 0.770 -> "0.77", 70.0 -> "70".
    private static func trimmed(_ value: Double, _ places: Int) -> String {
        var text = String(format: "%.\(places)f", value)
        if text.contains(".") {
            while text.hasSuffix("0") { text.removeLast() }
            if text.hasSuffix(".") { text.removeLast() }
        }
        return text == "-0" ? "0" : text
    }
}

private extension Double {
    var clamped01: Double { Swift.min(1, Swift.max(0, self)) }

    func rounded(toPlaces places: Int) -> Double {
        let factor = pow(10, Double(places))
        return (self * factor).rounded() / factor
    }
}
