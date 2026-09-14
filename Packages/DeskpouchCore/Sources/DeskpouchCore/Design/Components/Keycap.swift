import SwiftUI

/// A physical keycap for shortcuts. Tint gradient, tint border, 3px solid bottom shadow in bg, 1px inner highlight.
public struct Keycap: View {
    public enum Size: Sendable {
        case small   // 28 tall, 13pt label
        case large   // 34 tall, 15pt label

        var height: CGFloat { self == .small ? 28 : 34 }
        var fontSize: CGFloat { self == .small ? 13 : 15 }
    }

    let label: String
    let size: Size
    let width: CGFloat?

    public init(_ label: String, size: Size = .small, width: CGFloat? = nil) {
        self.label = label
        self.size = size
        self.width = width
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.keycap, style: .continuous)
        Text(label)
            .font(.dp(size.fontSize, .medium))
            .foregroundStyle(Theme.Colors.text)
            .padding(.horizontal, 9)
            .frame(minWidth: size.height)
            .frame(width: width, height: size.height)
            .background(
                shape.fill(Theme.Colors.card)
                    .overlay(
                        shape.fill(LinearGradient(
                            colors: [Theme.Colors.tint(0.14), Theme.Colors.tint(0.05)],
                            startPoint: .top, endPoint: .bottom
                        ))
                    )
            )
            .overlay(shape.strokeBorder(Theme.Colors.tint(0.18), lineWidth: 1))
            .overlay(alignment: .top) {
                // 1px inner top highlight
                Rectangle()
                    .fill(Color.white.opacity(0.12))
                    .frame(height: 1)
                    .padding(.horizontal, Theme.Radius.keycap)
                    .padding(.top, 1)
            }
            .background(shape.fill(Theme.Colors.bg).offset(y: 3))
            .fixedSize()
    }
}
