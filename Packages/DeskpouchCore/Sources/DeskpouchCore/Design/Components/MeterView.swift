import SwiftUI

/// Vertical bar meter. Bars are fully rounded, amber by default. Never a curve.
public struct MeterView: View {
    let levels: [Float]
    let barWidth: CGFloat
    let gap: CGFloat
    let minHeight: CGFloat
    let maxHeight: CGFloat
    let color: Color

    /// - Parameters:
    ///   - levels: one value in 0...1 per bar, oldest first.
    public init(
        levels: [Float],
        barWidth: CGFloat = 3,
        gap: CGFloat = 4,
        minHeight: CGFloat = 4,
        maxHeight: CGFloat = 30,
        color: Color = Theme.Colors.accentHigh
    ) {
        self.levels = levels
        self.barWidth = barWidth
        self.gap = gap
        self.minHeight = minHeight
        self.maxHeight = maxHeight
        self.color = color
    }

    public var body: some View {
        HStack(alignment: .center, spacing: gap) {
            ForEach(levels.indices, id: \.self) { i in
                Capsule()
                    .fill(color)
                    .frame(width: barWidth, height: height(for: levels[i]))
            }
        }
        .frame(height: maxHeight)
    }

    private func height(for level: Float) -> CGFloat {
        let l = CGFloat(min(max(level, 0), 1))
        return minHeight + (maxHeight - minHeight) * l
    }
}
