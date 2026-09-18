import DeskpouchCore
import SwiftUI
import ToolColor

struct ColorRow: View {
    let state: ShellState

    var body: some View {
        ToolRow(name: "Color", live: .none, open: { state.panelView = .tool(ColorToolView.toolID) }) {
            ColorTile()
        } status: {
            Text(state.colorSettings.summary)
                .foregroundStyle(Theme.Colors.textTertiary)
        } keys: {
            ForEach(Array(state.colorKey.symbols.enumerated()), id: \.offset) { _, symbol in
                Keycap(symbol)
            }
        }
        .opacity(state.colorKeyTaken ? 0.7 : 1)
    }
}

/// Dark tile with the eyedropper, ringed in a sweep of the app's three accents.
struct ColorTile: View {
    var size: CGFloat = 36

    var body: some View {
        let tile = RoundedRectangle(cornerRadius: Theme.Radius.tile * size / 36, style: .continuous)
        DropperIcon()
            .stroke(style: .icon(1.6))
            .foregroundStyle(Theme.Colors.text)
            .frame(width: size / 2, height: size / 2)
            .frame(width: size, height: size)
            .background(tile.fill(Theme.Colors.tint(0.06)))
            .overlay(
                tile.strokeBorder(
                    AngularGradient(
                        colors: [Theme.Colors.accentHigh, Theme.Colors.record, Theme.Colors.ok, Theme.Colors.accentHigh],
                        center: .center
                    ),
                    lineWidth: 1.2
                )
                .opacity(0.75)
            )
    }
}

/// Color: description and combo, chips, then format, Tailwind hints and shortcut rows.
struct ColorToolView: View {
    let state: ShellState
    let actions: MenuPanelActions

    static let toolID = "color"
    static let chips: [OutputAction] = [.copy, .history]

    /// A sample of each format, amber from the app's own accent.
    private static let example = SRGBColor(hex: 0xF59E0B)

    var body: some View {
        ToolCard(live: false, liveColor: Theme.Colors.accent) {
            HStack(spacing: 12) {
                ColorTile()
                Text("Any pixel on screen")
                    .font(.dp(12))
                    .foregroundStyle(Theme.Colors.textSecondary)
                Spacer(minLength: 8)
                HStack(spacing: 4) {
                    ForEach(Array(state.colorKey.symbols.enumerated()), id: \.offset) { _, symbol in
                        Keycap(symbol)
                    }
                }
                .opacity(state.colorKeyTaken ? 0.4 : 1)
                .help(state.colorKeyTaken ? "Another app owns this shortcut" : "Opens the loupe")
            }
            chipRow
            options
        }
    }

    private var chipRow: some View {
        let enabled = state.output.config(for: Self.toolID).actions
        return FlowLayout(spacing: 6) {
            ForEach(Self.chips, id: \.self) { action in
                Chip(action.label, isOn: enabled.contains(action)) {
                    actions.toggleOutput(Self.toolID, action)
                }
            }
        }
    }

    private var options: some View {
        VStack(spacing: 0) {
            RowDivider()
            OptionRows {
                OptionRow("Format") {
                    PopupPicker(
                        id: "color.format",
                        selection: Binding(get: { state.colorSettings.format }, set: { value in actions.updateColor { $0.format = value } }),
                        options: ColorFormat.allCases,
                        title: { $0.label },
                        detail: { $0.string(for: Self.example) }
                    )
                }
                OptionRow("Tailwind hints") {
                    ToggleSwitch("Tailwind hints", isOn: Binding(get: { state.colorSettings.tailwindHints }, set: { value in actions.updateColor { $0.tailwindHints = value } }))
                }
                OptionRow("Shortcut") {
                    ShortcutRecorder(.press(state.colorKey)) { kind in
                        if case .press(let combo) = kind { actions.setColorPressKey(combo) }
                    }
                }
            }
            .padding(.top, 4)
        }
    }
}

/// History tile for a picked colour: the colour itself, filling the tile.
struct ColorSwatchTile: View {
    let color: SRGBColor?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
        shape
            .fill(color.map { Color(.sRGB, red: $0.red, green: $0.green, blue: $0.blue) } ?? Theme.Colors.well)
            .overlay(shape.strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
            .frame(width: 44, height: 30)
    }
}

extension HistoryItem {
    /// The colour behind a colour row: the exact pixel logged with it, or the copied string parsed back for rows
    /// written before the `meta` column existed (exact for hex, rgb and SwiftUI, a unit or two off for the
    /// formats that round on the way out).
    var pickedColor: SRGBColor? {
        guard kind == .color else { return nil }
        if let srgb = meta?.srgb, let exact = ColorFormat.parse(srgb) { return exact }
        return text.flatMap(ColorFormat.parse)
    }

    /// "amber-500" or "≈ amber-500" for the row's second line; nil when nothing is close.
    var tailwindHint: String? {
        guard let color = pickedColor, let match = TailwindPalette.nearest(to: color) else { return nil }
        return match.isExact ? match.name : "≈ \(match.name)"
    }
}

/// Every format of one picked colour, under an expanded colour row. A line copies on click; the button is there
/// for the hit area and for VoiceOver.
struct ColorFormatsList: View {
    let color: SRGBColor
    let copy: @MainActor (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(ColorFormat.allCases.enumerated()), id: \.element) { index, format in
                if index > 0 { RowDivider() }
                row(format)
            }
        }
        .padding(.horizontal, 10)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.well, style: .continuous).fill(Theme.Colors.well.opacity(0.7)))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.well, style: .continuous).strokeBorder(Theme.Colors.tint(0.07), lineWidth: 1))
    }

    private func row(_ format: ColorFormat) -> some View {
        let value = format.string(for: color)
        return HStack(spacing: 8) {
            Text(format.label)
                .font(.dp(10, .semibold))
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundStyle(Theme.Colors.textTertiary)
                .frame(width: 54, alignment: .leading)
            // The SwiftUI initializer does not fit the panel on one line; it wraps rather than losing its middle.
            Text(value)
                .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.Colors.text)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            RowActionButton("Copy \(format.label)", icon: CopyIcon()) { copy(value) }
        }
        .padding(.vertical, 7)
        .frame(minHeight: 32)
        .contentShape(Rectangle())
        .onTapGesture { copy(value) }
    }
}

/// Chevron that opens a colour row's formats. Rotates when open.
struct FormatsDisclosure: View {
    let isOpen: Bool
    let action: @MainActor () -> Void

    var body: some View {
        Button(action: action) {
            ChevronIcon()
                .stroke(style: .icon(1.5))
                .foregroundStyle(Theme.Colors.text.opacity(isOpen ? 0.8 : 0.5))
                .rotationEffect(.degrees(isOpen ? 180 : 0))
                .frame(width: 12, height: 12)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.keycap, style: .continuous).fill(Theme.Colors.tint(isOpen ? 0.08 : 0.05)))
                .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.keycap, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(isOpen ? "Hide the other formats" : "Show every format")
        .accessibilityLabel(isOpen ? "Hide the other formats" : "Show every format")
    }
}
