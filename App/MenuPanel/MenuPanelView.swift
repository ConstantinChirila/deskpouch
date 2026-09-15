import DeskpouchCore
import SwiftUI

/// The panel: header, voice card, Recent, footer. General arrives in milestone 5.
struct MenuPanelView: View {
    let state: ShellState
    let actions: MenuPanelActions

    var body: some View {
        VStack(spacing: 16) {
            header
            if !state.hotkeyReady {
                PermissionCard(action: actions.requestPermission)
            }
            VoiceCard(state: state, actions: actions)
            if !state.recent.isEmpty {
                RecentSection(items: state.recent, count: state.historyCount, copy: actions.copyRecent)
            }
            footer
        }
        .padding(18)
        .frame(width: MenuPanelController.width)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous)
                .fill(Theme.panelGradient)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous)
                .strokeBorder(Theme.Colors.tint(0.12), lineWidth: 1)
        )
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1)
                .padding(.horizontal, Theme.Radius.panel)
                .padding(.top, 1)
        }
        .shadow(color: .black.opacity(0.65), radius: 35, y: 30)
        .shadow(color: .black.opacity(0.4), radius: 10, y: 8)
        .padding(.top, MenuPanelController.shadowInset.top)
        .padding(.bottom, MenuPanelController.shadowInset.bottom)
        .padding(.horizontal, MenuPanelController.shadowInset.left)
        .foregroundStyle(Theme.Colors.text)
    }

    private var header: some View {
        HStack {
            Text("Deskpouch")
                .font(.dp(15, .semibold))
                .tracking(-0.15)
            Spacer()
            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)
                    .shadow(color: statusColor.opacity(0.8), radius: 4)
                Text(statusText)
                    .font(.dp(11))
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
        }
    }

    private var statusColor: Color {
        state.isListening ? Theme.Colors.accent : (state.hotkeyReady ? Theme.Colors.ok : Theme.Colors.record)
    }

    private var statusText: String {
        state.isListening ? "Listening" : (state.hotkeyReady ? "Ready" : "Needs access")
    }

    private var footer: some View {
        HStack {
            HStack(spacing: 6) {
                GearIcon()
                    .stroke(style: .icon(1.5))
                    .frame(width: 14, height: 14)
                Text("General")
            }
            .opacity(0.5) // Milestone 5
            Spacer()
            Button(action: actions.quit) {
                Text("Quit  ⌘Q")
            }
            .buttonStyle(.plain)
        }
        .font(.dp(12))
        .foregroundStyle(Theme.Colors.textTertiary)
        .padding(.horizontal, 4)
    }
}

/// Voice tool card. Active (amber) while listening. Meter well shows the live meter; chips pick after-capture actions.
struct VoiceCard: View {
    let state: ShellState
    let actions: MenuPanelActions

    static let toolID = "voice"
    /// Notify is left out on purpose: the pill already says what happened. The recorder will use it.
    static let chips: [OutputAction] = [.paste, .copy, .history]

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                iconTile
                VStack(alignment: .leading, spacing: 2) {
                    Text("Voice").font(.dp(15, .semibold))
                    Text("Hold to talk, release to paste")
                        .font(.dp(12))
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                Spacer(minLength: 8)
                HStack(spacing: 6) {
                    Text("hold")
                        .font(.dp(10))
                        .tracking(0.6)
                        .textCase(.uppercase)
                        .foregroundStyle(Theme.Colors.textTertiary)
                    Keycap(state.holdKey.symbol, size: .large, width: 42)
                }
            }
            HStack(spacing: 12) {
                MeterView(levels: state.panelMeter.bars, barWidth: 3, gap: 3, minHeight: 4, maxHeight: 24, color: Theme.Colors.accent)
                Spacer()
                Text(state.voiceStatus)
                    .font(.dp(11))
                    .foregroundStyle(Theme.Colors.textFaint)
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.well, style: .continuous)
                    .fill(Theme.Colors.well)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.well, style: .continuous)
                    .strokeBorder(Theme.Colors.tint(0.08), lineWidth: 1)
            )
            chipRow
        }
        .padding(16)
        .background(shape.fill(Theme.Colors.card))
        .background(shape.stroke(Theme.Colors.accent(0.06), lineWidth: 4).padding(-2).opacity(state.isListening ? 1 : 0))
        .overlay(
            shape.fill(LinearGradient(
                stops: [
                    .init(color: Theme.Colors.accent(0.10), location: 0),
                    .init(color: Theme.Colors.accent(0.03), location: 0.6),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ))
            .allowsHitTesting(false)
            .opacity(state.isListening ? 1 : 0)
        )
        .overlay(shape.strokeBorder(state.isListening ? Theme.Colors.accent(0.30) : Theme.Colors.tint(0.10), lineWidth: 1))
        .animation(.easeOut(duration: 0.18), value: state.isListening)
        .onChange(of: state.isListening) { _, listening in
            if !listening { state.panelMeter.reset() }
        }
    }

    private var chipRow: some View {
        let enabled = state.output.config(for: Self.toolID).actions
        return FlowLayout(spacing: 6, trailingLast: true) {
            ForEach(Self.chips, id: \.self) { action in
                Chip(action.label, isOn: enabled.contains(action)) {
                    actions.toggleOutput(Self.toolID, action)
                }
            }
            HStack(spacing: 4) {
                Text("Options")
                ChevronIcon()
                    .stroke(style: .icon(1.4))
                    .frame(width: 10, height: 10)
            }
            .font(.dp(12))
            .foregroundStyle(Theme.Colors.textSecondary)
            .fixedSize()
            .padding(.horizontal, 6)
            .frame(height: 26)
            .opacity(0.5) // Milestone 5
        }
    }

    private var iconTile: some View {
        let tile = RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
        return MicIcon()
            .stroke(style: .icon(1.7))
            .foregroundStyle(Theme.Colors.accentInk)
            .frame(width: 18, height: 18)
            .frame(width: 36, height: 36)
            .background(
                tile.fill(LinearGradient(
                    colors: [Theme.Colors.accentHigh, Theme.Colors.accentLow],
                    startPoint: .top, endPoint: .bottom
                ))
            )
            .overlay(alignment: .top) {
                Rectangle().fill(Color.white.opacity(0.35)).frame(height: 1)
                    .padding(.horizontal, Theme.Radius.tile).padding(.top, 1)
            }
            .shadow(color: Theme.Colors.accent(0.35), radius: 8, y: 6)
    }
}

/// "Recent" label, total count, then one row per item (newest first). Times refresh every half minute while open.
struct RecentSection: View {
    let items: [HistoryItem]
    let count: Int
    let copy: @MainActor (HistoryItem) -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Recent")
                    .font(.dp(11, .semibold))
                    .tracking(0.66)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.Colors.textTertiary)
                Spacer()
                Text(count == 1 ? "1 item" : "\(count) items")
                    .font(.dp(11))
                    .foregroundStyle(Theme.Colors.textFaint)
            }
            .padding(.horizontal, 4)
            TimelineView(.periodic(from: .now, by: 30)) { context in
                ForEach(items) { item in
                    RecentRow(item: item, now: context.date, copy: { copy(item) })
                }
            }
        }
    }
}

struct RecentRow: View {
    let item: HistoryItem
    let now: Date
    let copy: @MainActor () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
        HStack(spacing: 12) {
            tile
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.dp(13, .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(meta)
                    .font(.dp(11))
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            RowActionButton(icon: CopyIcon(), action: copy)
                .help(item.text != nil ? "Copy transcript" : "Copy file")
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 10)
        .background(shape.fill(Theme.Colors.tint(0.03)))
        .overlay(shape.strokeBorder(Theme.Colors.tint(0.07), lineWidth: 1))
    }

    private var title: String {
        if let text = item.text, !text.isEmpty { return text }
        return item.fileURL?.lastPathComponent ?? "Capture"
    }

    private var meta: String {
        var parts = [RelativeTime.phrase(from: item.createdAt, now: now)]
        if let target = item.pastedInto {
            parts.append("pasted into \(target)")
        } else if let duration = item.duration {
            parts.append(TimeFormat.minutesSeconds(duration))
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var tile: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
        if item.text != nil {
            MicIcon()
                .stroke(style: .icon(1.7))
                .foregroundStyle(Theme.Colors.accentHigh)
                .frame(width: 14, height: 14)
                .frame(width: 44, height: 30)
                .background(shape.fill(Theme.Colors.accent(0.14)))
                .overlay(shape.strokeBorder(Theme.Colors.accent(0.25), lineWidth: 1))
        } else {
            // File capture: dark thumbnail placeholder with a duration badge.
            ZStack(alignment: .bottomTrailing) {
                shape.fill(LinearGradient(colors: [Color(hex: 0x3B42_52), Color(hex: 0x2226_2F)], startPoint: .topLeading, endPoint: .bottomTrailing))
                if let duration = item.duration {
                    Text(TimeFormat.minutesSeconds(duration))
                        .font(.dp(9))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .frame(height: 12)
                        .background(RoundedRectangle(cornerRadius: 3).fill(Color.black.opacity(0.6)))
                        .padding([.trailing, .bottom], 3)
                }
            }
            .frame(width: 44, height: 30)
            .overlay(shape.strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
        }
    }
}

/// Shown until the event tap can be created.
struct PermissionCard: View {
    let action: @MainActor () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Accessibility access needed").font(.dp(13, .medium))
                Text("For the hold-to-talk key and pasting into apps.")
                    .font(.dp(12))
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer(minLength: 8)
            Button(action: action) {
                Text("Open Settings")
                    .font(.dp(12, .medium))
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                            .fill(Theme.Colors.tint(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                            .strokeBorder(Theme.Colors.tint(0.14), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(shape.fill(Theme.Colors.card))
        .overlay(shape.strokeBorder(Theme.Colors.record(0.30), lineWidth: 1))
    }
}
