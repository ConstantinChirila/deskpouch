import DeskpouchCore
import SwiftUI

/// Fills one screen's overlay window. Draws the loupe only on the screen the cursor is on.
struct LoupeScreenView: View {
    let model: LoupeModel
    let screen: LoupeScreen

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            if model.screenID == screen.id {
                let center = screen.localPoint(of: model.pixel)
                let layout = LoupeLayout(center: center, bounds: CGRect(origin: .zero, size: screen.frame.size))
                MagnifierView(model: model)
                    .position(center)
                VStack(spacing: 6) {
                    ReadoutView(model: model)
                    KeyHints()
                }
                .fixedSize()
                .position(layout.readoutCenter)
            }
        }
        .frame(width: screen.frame.width, height: screen.frame.height)
    }
}

/// Where the readout sits: under the magnifier, above it near the bottom edge, kept inside the screen.
struct LoupeLayout {
    static let magnifierSide = MagnifierView.side
    static let gap: CGFloat = 10
    /// Readout plus key hints, for placement only.
    static let readoutSize = CGSize(width: 250, height: 58)

    let center: CGPoint
    let bounds: CGRect

    var readoutCenter: CGPoint {
        let half = Self.magnifierSide / 2
        let below = center.y + half + Self.gap + Self.readoutSize.height / 2
        let y = below + Self.readoutSize.height / 2 > bounds.maxY - 8
            ? center.y - half - Self.gap - Self.readoutSize.height / 2
            : below
        let halfWidth = Self.readoutSize.width / 2
        let x = min(max(center.x, bounds.minX + halfWidth + 8), bounds.maxX - halfWidth - 8)
        return CGPoint(x: x, y: y)
    }
}

/// 11x11 pixels at 12 pt each in a squircle well, centre pixel ringed, amber notches pointing at it.
struct MagnifierView: View {
    let model: LoupeModel

    nonisolated static let cell: CGFloat = 12
    nonisolated static let inner = CGFloat(LoupeModel.gridSize) * cell
    nonisolated static let frame: CGFloat = 5
    nonisolated static let side = inner + frame * 2

    var body: some View {
        let grid = model.grid
        let outer = RoundedRectangle(cornerRadius: 26, style: .continuous)
        let well = RoundedRectangle(cornerRadius: 21, style: .continuous)
        Canvas { context, _ in
            let n = LoupeModel.gridSize
            let cell = Self.cell
            if grid.isEmpty {
                context.fill(Path(CGRect(x: 0, y: 0, width: Self.inner, height: Self.inner)), with: .color(Theme.Colors.well))
            } else {
                for (index, color) in grid.enumerated() {
                    let rect = CGRect(x: CGFloat(index % n) * cell, y: CGFloat(index / n) * cell, width: cell, height: cell)
                    context.fill(Path(rect), with: .color(color.map(Color.init(rgb:)) ?? Theme.Colors.well))
                }
            }
            var lines = Path()
            for i in 1..<n {
                let offset = CGFloat(i) * cell
                lines.move(to: CGPoint(x: offset, y: 0)); lines.addLine(to: CGPoint(x: offset, y: Self.inner))
                lines.move(to: CGPoint(x: 0, y: offset)); lines.addLine(to: CGPoint(x: Self.inner, y: offset))
            }
            context.stroke(lines, with: .color(.black.opacity(grid.isEmpty ? 0.35 : 0.10)), lineWidth: 0.5)

            let middle = CGFloat(n / 2) * cell
            let centre = CGRect(x: middle, y: middle, width: cell, height: cell)
            context.stroke(Path(centre.insetBy(dx: -1, dy: -1)), with: .color(.black.opacity(0.75)), lineWidth: 1.5)
            context.stroke(Path(centre.insetBy(dx: 0.25, dy: 0.25)), with: .color(.white), lineWidth: 1.5)
        }
        .frame(width: Self.inner, height: Self.inner)
        .clipShape(well)
        .overlay(well.strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
        .padding(Self.frame)
        .background(outer.fill(Theme.panelGradient))
        .overlay(outer.strokeBorder(Theme.Colors.tint(0.16), lineWidth: 1))
        .overlay { notches }
        .shadow(color: .black.opacity(0.5), radius: 18, y: 10)
        .frame(width: Self.side, height: Self.side)
    }

    /// Short amber ticks in the frame, lined up with the centre row and column.
    private var notches: some View {
        let long: CGFloat = 8
        let thick: CGFloat = 2
        let mid = Self.side / 2
        let edge = Self.frame / 2
        return ZStack {
            Capsule().frame(width: thick, height: long).position(x: mid, y: edge)
            Capsule().frame(width: thick, height: long).position(x: mid, y: Self.side - edge)
            Capsule().frame(width: long, height: thick).position(x: edge, y: mid)
            Capsule().frame(width: long, height: thick).position(x: Self.side - edge, y: mid)
        }
        .foregroundStyle(Theme.Colors.accentHigh)
        .frame(width: Self.side, height: Self.side)
    }
}

/// Swatch, the value a click copies, and the Tailwind hint.
struct ReadoutView: View {
    let model: LoupeModel

    var body: some View {
        let shape = Capsule(style: .continuous)
        HStack(spacing: 10) {
            if let color = model.centerColor, let value = model.value {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(rgb: color))
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.white.opacity(0.22), lineWidth: 1))
                    .frame(width: 20, height: 20)
                Text(displayed(value, color: color))
                    .font(.system(size: 12.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.Colors.text)
                if model.settings.tailwindHints {
                    Rectangle()
                        .fill(Theme.Colors.tint(0.16))
                        .frame(width: 1, height: 14)
                    hint
                }
            } else {
                ProgressView()
                    .controlSize(.mini)
                    .tint(Theme.Colors.accentHigh)
                    .frame(width: 20, height: 20)
                Text("Reading screen")
                    .font(.dp(12, .medium))
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .padding(.leading, 5)
        .padding(.trailing, 14)
        .frame(height: 30)
        .background(shape.fill(Theme.panelGradient))
        .overlay(shape.strokeBorder(Theme.Colors.tint(0.16), lineWidth: 1))
        .shadow(color: .black.opacity(0.45), radius: 12, y: 6)
    }

    /// The SwiftUI initializer is too long for the loupe; its hex stands in (the click still copies the initializer).
    private func displayed(_ value: String, color: SRGBColor) -> String {
        model.settings.format == .swiftUI ? color.hex : value
    }

    @ViewBuilder private var hint: some View {
        if let match = model.match {
            Text(match.isExact ? match.name : "≈ \(match.name)")
                .font(.dp(12, .medium))
                .foregroundStyle(Theme.Colors.accentHigh)
        } else {
            Text("custom")
                .font(.dp(12))
                .foregroundStyle(Theme.Colors.textFaint)
        }
    }
}

/// "Click copies · ←↑↓→ nudge · esc", on its own dark capsule so it reads over anything.
struct KeyHints: View {
    var body: some View {
        HStack(spacing: 5) {
            Text("Click copies")
            dot
            Text("←↑↓→").font(.system(size: 10, weight: .medium))
            Text("nudge")
            dot
            Text("esc")
        }
        .font(.dp(10.5))
        .foregroundStyle(Theme.Colors.textSecondary)
        .padding(.horizontal, 10)
        .frame(height: 20)
        .background(Capsule(style: .continuous).fill(Theme.Colors.bg.opacity(0.82)))
    }

    private var dot: some View {
        Circle().fill(Theme.Colors.textFaint).frame(width: 2.5, height: 2.5)
    }
}

extension Color {
    init(rgb: SRGBColor) {
        self.init(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}
