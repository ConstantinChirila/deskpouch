import AppKit
import SwiftUI

/// Design tokens from `design/DESIGN.md`. "Mint ground, amber accent".
public enum Theme {
    public enum Colors {
        // Ground
        public static let bg = Color(hex: 0x0D12_11)
        public static let panelTop = Color(hex: 0x1A23_20)
        public static let panelBottom = Color(hex: 0x121A_17)
        public static let card = Color(hex: 0x161F_1B)
        public static let well = Color(hex: 0x0D14_11)

        // Text
        public static let text = Color(hex: 0xE8F5_EF)
        public static let textSecondary = text.opacity(0.62)
        public static let textTertiary = text.opacity(0.58)
        public static let textFaint = text.opacity(0.55)

        // Accent
        public static let accent = Color(hex: 0xF59E_0B)
        public static let accentHigh = Color(hex: 0xFBBF_24)
        public static let accentLow = Color(hex: 0xD977_06)
        public static let accentInk = Color(hex: 0x1C19_17)

        // Status
        public static let ok = Color(hex: 0x2DD4_A3)
        public static let record = Color(hex: 0xFB71_85)

        /// rgb(180,255,220) at the given alpha. Every hairline, border and subtle fill.
        public static func tint(_ alpha: Double) -> Color {
            Color(red: 180 / 255, green: 1, blue: 220 / 255).opacity(alpha)
        }

        public static func accent(_ alpha: Double) -> Color { accent.opacity(alpha) }
        public static func ok(_ alpha: Double) -> Color { ok.opacity(alpha) }
        public static func record(_ alpha: Double) -> Color { record.opacity(alpha) }
    }

    /// AppKit colours for surfaces drawn without SwiftUI (menubar icon).
    public enum NSColors {
        public static let bg = NSColor(hex: 0x0D12_11)
        public static let text = NSColor(hex: 0xE8F5_EF)
        public static let accent = NSColor(hex: 0xF59E_0B)
        public static let accentHigh = NSColor(hex: 0xFBBF_24)
        public static let record = NSColor(hex: 0xFB71_85)
        public static let ok = NSColor(hex: 0x2DD4_A3)
        public static let accentInk = NSColor(hex: 0x1C19_17)
    }

    public enum Radius {
        public static let panel: CGFloat = 18
        public static let card: CGFloat = 14
        public static let row: CGFloat = 12
        public static let well: CGFloat = 10
        public static let tile: CGFloat = 10
        public static let keycap: CGFloat = 8
        public static let control: CGFloat = 7
        public static let pill: CGFloat = 999
    }

    public static let panelGradient = LinearGradient(
        colors: [Colors.panelTop, Colors.panelBottom],
        startPoint: .top,
        endPoint: .bottom
    )
}

extension Color {
    public init(hex: UInt32, alpha: Double = 1) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

extension NSColor {
    public convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}
