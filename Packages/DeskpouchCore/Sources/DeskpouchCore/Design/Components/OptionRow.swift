import SwiftUI

/// 40pt option row: label (13) with an optional 11pt faint sub-label on the left, a control on the right.
public struct OptionRow<Control: View>: View {
    let label: String
    let detail: String?
    @ViewBuilder let control: () -> Control

    public init(_ label: String, detail: String? = nil, @ViewBuilder control: @escaping () -> Control) {
        self.label = label
        self.detail = detail
        self.control = control
    }

    public var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.dp(13)).foregroundStyle(Theme.Colors.text)
                if let detail {
                    Text(detail).font(.dp(11)).foregroundStyle(Theme.Colors.textTertiary).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            control()
        }
        .padding(.vertical, 6)
        .frame(minHeight: 40)
    }
}

/// Hairline between option rows.
public struct RowDivider: View {
    public init() {}
    public var body: some View {
        Rectangle().fill(Theme.Colors.tint(0.08)).frame(height: 1)
    }
}

/// Rows stacked with hairlines between them, as they appear inside an expanded card or a General group.
public struct OptionRows<Content: View>: View {
    @ViewBuilder let content: () -> Content

    public init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    public var body: some View {
        _VariadicView.Tree(RowsLayout()) { content() }
    }

    private struct RowsLayout: _VariadicView_UnaryViewRoot {
        func body(children: _VariadicView.Children) -> some View {
            VStack(spacing: 0) {
                ForEach(Array(children.enumerated()), id: \.element.id) { index, child in
                    if index > 0 { RowDivider() }
                    child
                }
            }
        }
    }
}

/// Card holding option rows in the General view: card fill, tint border, 4/16 padding.
public struct OptionsGroup<Content: View>: View {
    @ViewBuilder let content: () -> Content

    public init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
        OptionRows(content: content)
            .padding(.vertical, 4)
            .padding(.horizontal, 16)
            .background(shape.fill(Theme.Colors.card))
            .overlay(shape.strokeBorder(Theme.Colors.tint(0.10), lineWidth: 1))
    }
}

/// 28x17 switch. On: amber track with a glow, accent-ink knob. Off: tint track, text-coloured knob.
/// `label` is what VoiceOver reads; the switch itself shows no text.
public struct ToggleSwitch: View {
    let label: String
    @Binding var isOn: Bool

    public init(_ label: String, isOn: Binding<Bool>) {
        self.label = label
        _isOn = isOn
    }

    public var body: some View {
        Button {
            isOn.toggle()
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule().fill(isOn ? Theme.Colors.accent : Theme.Colors.tint(0.14))
                Circle()
                    .fill(isOn ? Theme.Colors.accentInk : Theme.Colors.text)
                    .frame(width: 13, height: 13)
                    .padding(2)
            }
            .frame(width: 28, height: 17)
            .shadow(color: isOn ? Theme.Colors.accent(0.35) : .clear, radius: 5)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: isOn)
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(.isToggle)
    }
}

/// 26 tall row button: tint fill 0.06, border 0.14. `chevron` turns it into the popup trigger.
public struct RowButton: View {
    let title: String
    let chevron: Bool
    let enabled: Bool
    let action: @MainActor () -> Void

    public init(_ title: String, chevron: Bool = false, enabled: Bool = true, action: @escaping @MainActor () -> Void) {
        self.title = title
        self.chevron = chevron
        self.enabled = enabled
        self.action = action
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title).font(.dp(12)).lineLimit(1)
                if chevron {
                    ChevronIcon().stroke(style: .icon(1.4)).frame(width: 10, height: 10)
                }
            }
            .foregroundStyle(Theme.Colors.text)
            .padding(.leading, 10)
            .padding(.trailing, chevron ? 8 : 10)
            .frame(height: 26)
            .background(shape.fill(Theme.Colors.tint(0.06)))
            .overlay(shape.strokeBorder(Theme.Colors.tint(0.14), lineWidth: 1))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
    }
}

// MARK: Popups

/// One entry in a dropdown.
public struct PopupItem: Identifiable, Sendable {
    public let id: Int
    public let title: String
    public let detail: String?
    public let selected: Bool

    public init(id: Int, title: String, detail: String? = nil, selected: Bool) {
        self.id = id
        self.title = title
        self.detail = detail
        self.selected = selected
    }
}

/// The one dropdown a panel can show. Buttons open it; the `popupHost` modifier at the panel root draws it
/// under the button's anchor and closes it on an outside click.
@MainActor
@Observable
public final class PopupController {
    public struct Open {
        public let anchorID: AnyHashable
        public let items: [PopupItem]
        public let onSelect: @MainActor (Int) -> Void
    }

    public private(set) var open: Open?

    public init() {}

    public var isOpen: Bool { open != nil }

    public func toggle(_ anchorID: AnyHashable, items: [PopupItem], onSelect: @escaping @MainActor (Int) -> Void) {
        if open?.anchorID == anchorID {
            close()
        } else {
            open = Open(anchorID: anchorID, items: items, onSelect: onSelect)
        }
    }

    public func close() {
        open = nil
    }
}

/// Popup trigger: a row button with a chevron that reports its bounds so the dropdown can hang off it.
public struct PopupButton: View {
    let id: AnyHashable
    let title: String
    let items: [PopupItem]
    let onSelect: @MainActor (Int) -> Void
    @Environment(PopupController.self) private var popups

    public init(id: AnyHashable, title: String, items: [PopupItem], onSelect: @escaping @MainActor (Int) -> Void) {
        self.id = id
        self.title = title
        self.items = items
        self.onSelect = onSelect
    }

    public var body: some View {
        RowButton(title, chevron: true) {
            popups.toggle(id, items: items, onSelect: onSelect)
        }
        .anchorPreference(key: PopupAnchorKey.self, value: .bounds) { [id: $0] }
    }
}

/// Convenience for "pick one of these values" rows.
public struct PopupPicker<Value: Hashable>: View {
    let id: AnyHashable
    @Binding var selection: Value
    let options: [Value]
    let title: (Value) -> String
    let detail: (Value) -> String?

    public init(
        id: AnyHashable, selection: Binding<Value>, options: [Value],
        title: @escaping (Value) -> String, detail: @escaping (Value) -> String? = { _ in nil }
    ) {
        self.id = id
        _selection = selection
        self.options = options
        self.title = title
        self.detail = detail
    }

    public var body: some View {
        PopupButton(
            id: id,
            title: title(selection),
            items: options.enumerated().map { index, value in
                PopupItem(id: index, title: title(value), detail: detail(value), selected: value == selection)
            }
        ) { index in
            selection = options[index]
        }
    }
}

public struct PopupAnchorKey: PreferenceKey {
    nonisolated(unsafe) public static let defaultValue: [AnyHashable: Anchor<CGRect>] = [:]
    public static func reduce(value: inout [AnyHashable: Anchor<CGRect>], nextValue: () -> [AnyHashable: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    /// Draws the open dropdown over this view, right-aligned under its button, with a click-away catcher.
    public func popupHost(_ popups: PopupController) -> some View {
        modifier(PopupHostModifier(popups: popups))
    }
}

private struct PopupHostModifier: ViewModifier {
    let popups: PopupController

    func body(content: Content) -> some View {
        content
            .environment(popups)
            .overlayPreferenceValue(PopupAnchorKey.self) { anchors in
                if let open = popups.open, let anchor = anchors[open.anchorID] {
                    GeometryReader { proxy in
                        let rect = proxy[anchor]
                        ZStack(alignment: .topLeading) {
                            Color.clear
                                .contentShape(Rectangle())
                                .onTapGesture { popups.close() }
                            PopupDropdown(items: open.items) { index in
                                popups.close()
                                open.onSelect(index)
                            }
                            .fixedSize()
                            .alignmentGuide(.leading) { $0[.trailing] - rect.maxX }
                            .alignmentGuide(.top) { _ in -(rect.maxY + 4) }
                        }
                    }
                    .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.12), value: popups.isOpen)
    }
}

/// The dropdown itself: panel gradient, tint border, 28pt rows, check on the selected one, hover highlight.
struct PopupDropdown: View {
    let items: [PopupItem]
    let select: @MainActor (Int) -> Void
    @State private var hovered: Int?

    /// Rows shown before the list scrolls.
    static let visibleRows = 8

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.well, style: .continuous)
        ScrollView(.vertical) {
            rows
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(height: CGFloat(min(items.count, Self.visibleRows)) * 29 - 1)
        .padding(4)
        .frame(minWidth: 160)
        .background(shape.fill(Theme.panelGradient))
        .overlay(shape.strokeBorder(Theme.Colors.tint(0.16), lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 18, y: 12)
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(items) { item in
                Button {
                    select(item.id)
                } label: {
                    HStack(spacing: 8) {
                        CheckIcon()
                            .stroke(style: .icon(2.2))
                            .frame(width: 9, height: 9)
                            .foregroundStyle(Theme.Colors.accentHigh)
                            .opacity(item.selected ? 1 : 0)
                        Text(item.title).font(.dp(12, item.selected ? .medium : .regular))
                        if let detail = item.detail {
                            Spacer(minLength: 12)
                            Text(detail).font(.dp(11)).foregroundStyle(Theme.Colors.textTertiary)
                        }
                    }
                    .foregroundStyle(Theme.Colors.text)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                            .fill(hovered == item.id ? Theme.Colors.tint(0.08) : .clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovered = $0 ? item.id : (hovered == item.id ? nil : hovered) }
            }
        }
    }
}
