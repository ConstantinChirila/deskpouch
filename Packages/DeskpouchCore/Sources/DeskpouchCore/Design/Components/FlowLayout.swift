import SwiftUI

/// Left-to-right, wrapping to new lines when the row is full. Rows are as tall as their tallest item.
/// `trailingLast` pushes the final subview to the right edge of its line when there is room (the "Options" disclosure).
public struct FlowLayout: Layout {
    public var spacing: CGFloat
    public var lineSpacing: CGFloat
    public var trailingLast: Bool

    public init(spacing: CGFloat = 6, lineSpacing: CGFloat = 6, trailingLast: Bool = false) {
        self.spacing = spacing
        self.lineSpacing = lineSpacing
        self.trailingLast = trailingLast
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let lines = arrange(subviews, width: width)
        let height = lines.reduce(0) { $0 + $1.height } + CGFloat(max(0, lines.count - 1)) * lineSpacing
        let usedWidth = lines.map(\.width).max() ?? 0
        return CGSize(width: width.isFinite ? width : usedWidth, height: height)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        let lines = arrange(subviews, width: bounds.width)
        for (lineIndex, line) in lines.enumerated() {
            var x = bounds.minX
            for (i, index) in line.indices.enumerated() {
                let size = line.sizes[i]
                let isLast = trailingLast && lineIndex == lines.count - 1 && index == subviews.count - 1
                if isLast { x = max(x, bounds.maxX - size.width) }
                let dy = (line.height - size.height) / 2
                subviews[index].place(at: CGPoint(x: x, y: y + dy), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += line.height + lineSpacing
        }
    }

    private struct Line {
        var indices: [Int] = []
        var sizes: [CGSize] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Line] {
        var lines: [Line] = []
        var current = Line()
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if !current.indices.isEmpty, needed > width {
                lines.append(current)
                current = Line()
            }
            current.indices.append(index)
            current.sizes.append(size)
            current.width = current.indices.count == 1 ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
        }
        if !current.indices.isEmpty { lines.append(current) }
        return lines
    }
}
