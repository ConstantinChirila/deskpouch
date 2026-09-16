import SwiftUI

/// Toggle chip, 26 tall pill. On: amber fill 0.16, border 0.40, accent-high text, check. Off: tint fill 0.04, border 0.12.
public struct Chip: View {
    let label: String
    let isOn: Bool
    let action: @MainActor () -> Void

    public init(_ label: String, isOn: Bool, action: @escaping @MainActor () -> Void) {
        self.label = label
        self.isOn = isOn
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isOn {
                    CheckIcon()
                        .stroke(style: .icon(2.4))
                        .frame(width: 10, height: 10)
                        .transition(.scale.combined(with: .opacity))
                }
                Text(label)
                    .font(.dp(12, isOn ? .medium : .regular))
                    .lineLimit(1)
            }
            .fixedSize()
            .foregroundStyle(isOn ? Theme.Colors.accentHigh : Theme.Colors.textSecondary)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(Capsule().fill(isOn ? Theme.Colors.accent(0.16) : Theme.Colors.tint(0.04)))
            .overlay(Capsule().strokeBorder(isOn ? Theme.Colors.accent(0.40) : Theme.Colors.tint(0.12), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: isOn)
    }
}

/// 28px square action button used on Recent rows. Tint fill 0.05, icon at 0.6.
/// `label` is both the tooltip and what VoiceOver reads, since the button shows only an icon.
public struct RowActionButton<Icon: Shape>: View {
    let label: String
    let icon: Icon
    let action: @MainActor () -> Void

    public init(_ label: String, icon: Icon, action: @escaping @MainActor () -> Void) {
        self.label = label
        self.icon = icon
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            icon.stroke(style: .icon(1.5))
                .foregroundStyle(Theme.Colors.text.opacity(0.6))
                .frame(width: 14, height: 14)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.keycap, style: .continuous).fill(Theme.Colors.tint(0.05)))
                .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.keycap, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}
