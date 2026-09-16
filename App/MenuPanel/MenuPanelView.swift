import DeskpouchCore
import SwiftUI
import ToolScreenRecorder
import ToolVoice

/// The panel: main view (header, voice card, screen card, Recent, footer) or the General view behind a back
/// chevron. Content is top-aligned in a window that reaches the bottom of the screen; clicks below it close.
struct MenuPanelView: View {
    let state: ShellState
    let actions: MenuPanelActions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .top) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { actions.closePanel() }
            panel
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .foregroundStyle(Theme.Colors.text)
    }

    private var panel: some View {
        Group {
            switch state.panelView {
            case .main:
                MainPanelView(state: state, actions: actions)
                    .transition(slide(from: .leading))
            case .general:
                GeneralView(state: state, actions: actions)
                    .transition(slide(from: .trailing))
            case .tool(let id):
                ToolView(toolID: id, state: state, actions: actions)
                    .transition(slide(from: .trailing))
            case .history:
                HistoryView(state: state, actions: actions)
                    .transition(slide(from: .trailing))
            }
        }
        .padding(18)
        .frame(width: MenuPanelController.width)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
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
        .popupHost(state.popups)
        .animation(.easeOut(duration: 0.2), value: state.panelView)
        .animation(.easeOut(duration: 0.15), value: state.confirmingClear)
        // Spring in from the menubar icon: slight scale from the top edge plus a fade.
        .scaleEffect(state.panelPresented || reduceMotion ? 1 : 0.96, anchor: .top)
        .opacity(state.panelPresented ? 1 : 0)
        .animation(.spring(duration: 0.22, bounce: 0.18), value: state.panelPresented)
        .padding(.top, MenuPanelController.shadowInset.top)
        .padding(.bottom, MenuPanelController.shadowInset.bottom)
        .padding(.horizontal, MenuPanelController.shadowInset.left)
    }

    /// Views slide in from the side, or just fade with Reduce Motion on.
    private func slide(from edge: Edge) -> AnyTransition {
        reduceMotion ? .opacity : .move(edge: edge).combined(with: .opacity)
    }
}

/// Header, one row per tool, Recent, footer. A row opens the tool's own view.
struct MainPanelView: View {
    let state: ShellState
    let actions: MenuPanelActions

    var body: some View {
        VStack(spacing: 16) {
            header
            if !state.hotkeyReady {
                PermissionCard(action: actions.requestPermission)
            }
            ToolsSection(state: state)
            if !state.recent.isEmpty {
                RecentSection(items: state.recent, count: state.historyCount, thumbnails: state.thumbnails,
                              copy: actions.copyRecent, reveal: actions.revealRecent) {
                    state.popups.close()
                    state.historyQuery = ""
                    state.historyFilter = .all
                    actions.loadHistory(false)
                    state.panelView = .history
                }
            }
            footer
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            BrandMark(size: 22)
            Text("Deskpouch")
                .font(.dp(15, .semibold))
                .tracking(-0.15)
            Spacer()
            StatusDot(state: state)
        }
    }

    private var footer: some View {
        HStack {
            Button {
                state.popups.close()
                state.panelView = .general
            } label: {
                HStack(spacing: 6) {
                    GearIcon()
                        .stroke(style: .icon(1.5))
                        .frame(width: 14, height: 14)
                    Text("General")
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
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

/// Status dot plus word: Recording, Listening, Ready, Needs access.
struct StatusDot: View {
    let state: ShellState

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
                .shadow(color: color.opacity(0.8), radius: 4)
            Text(text)
                .font(.dp(11))
                .foregroundStyle(Theme.Colors.textTertiary)
        }
    }

    private var isRecording: Bool {
        if case .recording = state.activity { return true }
        return false
    }

    private var color: Color {
        if isRecording { return Theme.Colors.record }
        return state.isListening ? Theme.Colors.accent : (state.hotkeyReady ? Theme.Colors.ok : Theme.Colors.record)
    }

    private var text: String {
        if isRecording { return "Recording" }
        return state.isListening ? "Listening" : (state.hotkeyReady ? "Ready" : "Needs access")
    }
}

/// "Tools" label, count, then one row per tool.
struct ToolsSection: View {
    let state: ShellState

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text("Tools")
                    .font(.dp(11, .semibold))
                    .tracking(0.66)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.Colors.textTertiary)
                Spacer()
                Text("2")
                    .font(.dp(11))
                    .foregroundStyle(Theme.Colors.textFaint)
            }
            .padding(.horizontal, 4)
            VoiceRow(state: state)
            ScreenRow(state: state)
        }
    }
}

/// A tool's row on the main view: tile, name, one-line status, shortcut keycaps, chevron. Amber while listening,
/// pink while recording.
struct ToolRow<Tile: View, Status: View, Keys: View>: View {
    enum Live { case none, listening, recording }

    let name: String
    let live: Live
    let open: @MainActor () -> Void
    @ViewBuilder let tile: () -> Tile
    @ViewBuilder let status: () -> Status
    @ViewBuilder let keys: () -> Keys

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
        Button(action: open) {
            HStack(spacing: 12) {
                tile()
                VStack(alignment: .leading, spacing: 3) {
                    Text(name).font(.dp(13, .medium)).foregroundStyle(Theme.Colors.text)
                    status()
                        .font(.dp(11))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 4) { keys() }
                ChevronIcon()
                    .stroke(style: .icon(1.4))
                    .rotationEffect(.degrees(-90))
                    .foregroundStyle(Theme.Colors.text.opacity(0.45))
                    .frame(width: 10, height: 10)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background(shape.fill(Theme.Colors.tint(0.03)))
            .background(shape.stroke(liveColor.opacity(0.06), lineWidth: 4).padding(-2).opacity(live == .none ? 0 : 1))
            .overlay(
                shape.fill(LinearGradient(
                    stops: [
                        .init(color: liveColor.opacity(0.10), location: 0),
                        .init(color: liveColor.opacity(0.03), location: 0.6),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
                .allowsHitTesting(false)
                .opacity(live == .none ? 0 : 1)
            )
            .overlay(shape.strokeBorder(live == .none ? Theme.Colors.tint(0.07) : liveColor.opacity(0.30), lineWidth: 1))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.18), value: live)
    }

    private var liveColor: Color {
        live == .recording ? Theme.Colors.record : Theme.Colors.accent
    }
}

struct VoiceRow: View {
    let state: ShellState

    var body: some View {
        ToolRow(name: "Voice", live: state.isListening ? .listening : .none, open: { state.panelView = .tool(VoiceToolView.toolID) }) {
            VoiceTile()
        } status: {
            if state.isListening {
                HStack(spacing: 6) {
                    MeterView(levels: Array(state.panelMeter.bars.suffix(7)), barWidth: 2, gap: 2, minHeight: 4, maxHeight: 13, color: Theme.Colors.accentHigh)
                    Text("Listening")
                }
                .foregroundStyle(Theme.Colors.accentHigh)
            } else {
                Text("Ready · hold to talk").foregroundStyle(Theme.Colors.textTertiary)
            }
        } keys: {
            Keycap(state.holdKey.symbol, width: 42)
        }
    }
}

struct ScreenRow: View {
    let state: ShellState

    var body: some View {
        let recording: Date? = { if case .recording(let since) = state.activity { return since } else { return nil } }()
        ToolRow(name: "Record screen", live: recording == nil ? .none : .recording, open: { state.panelView = .tool(ScreenToolView.toolID) }) {
            ScreenTile()
        } status: {
            if let since = recording {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    HStack(spacing: 6) {
                        Circle().fill(Theme.Colors.record).frame(width: 6, height: 6)
                            .shadow(color: Theme.Colors.record(0.8), radius: 4)
                        Text("Recording · \(TimeFormat.minutesSeconds(context.date.timeIntervalSince(since)))")
                            .monospacedDigit()
                    }
                    .foregroundStyle(Theme.Colors.record)
                }
            } else {
                Text("Ready · \(state.recorderSettings.quality == .high ? "1080p" : "Native") · \(state.recorderSettings.frameRate) fps")
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
        } keys: {
            ForEach(Array(state.screenKey.symbols.enumerated()), id: \.offset) { _, symbol in
                Keycap(symbol)
            }
        }
        .opacity(state.screenKeyTaken ? 0.7 : 1)
    }
}

/// Amber gradient tile with the mic.
struct VoiceTile: View {
    var body: some View {
        let tile = RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
        MicIcon()
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

/// Tint tile with the display glyph.
struct ScreenTile: View {
    var body: some View {
        let tile = RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
        ScreenIcon()
            .stroke(style: .icon(1.6))
            .foregroundStyle(Theme.Colors.text)
            .frame(width: 18, height: 18)
            .frame(width: 36, height: 36)
            .background(tile.fill(Theme.Colors.tint(0.06)))
            .overlay(tile.strokeBorder(Theme.Colors.tint(0.14), lineWidth: 1))
            .overlay(alignment: .top) {
                Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1)
                    .padding(.horizontal, Theme.Radius.tile).padding(.top, 1)
            }
    }
}

/// Header of a pushed view: back tile, title, status dot.
struct SubviewHeader: View {
    let title: String
    let state: ShellState
    let back: @MainActor () -> Void

    var body: some View {
        HStack {
            Button(action: back) {
                HStack(spacing: 8) {
                    ChevronIcon()
                        .stroke(style: .icon(1.6))
                        .rotationEffect(.degrees(90))
                        .foregroundStyle(Theme.Colors.text.opacity(0.7))
                        .frame(width: 12, height: 12)
                        .frame(width: 24, height: 24)
                        .background(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous).fill(Theme.Colors.tint(0.06)))
                        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous).strokeBorder(Theme.Colors.tint(0.12), lineWidth: 1))
                    Text(title)
                        .font(.dp(15, .semibold))
                        .tracking(-0.15)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Back")
            Spacer()
            StatusDot(state: state)
        }
    }
}

/// One tool's view: header, then its card with chips and options always open.
struct ToolView: View {
    let toolID: String
    let state: ShellState
    let actions: MenuPanelActions

    var body: some View {
        VStack(spacing: 16) {
            SubviewHeader(title: title, state: state) {
                state.popups.close()
                state.panelView = .main
            }
            switch toolID {
            case VoiceToolView.toolID: VoiceToolView(state: state, actions: actions)
            case ScreenToolView.toolID: ScreenToolView(state: state, actions: actions)
            default: EmptyView()
            }
        }
    }

    private var title: String {
        switch toolID {
        case VoiceToolView.toolID: "Voice"
        case ScreenToolView.toolID: "Record screen"
        default: toolID
        }
    }
}

/// Card chrome shared by the tool views. Amber ring while the tool is live.
struct ToolCard<Content: View>: View {
    let live: Bool
    let liveColor: Color
    @ViewBuilder let content: () -> Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
        VStack(spacing: 14, content: content)
            .padding(16)
            .background(shape.fill(Theme.Colors.card))
            .background(shape.stroke(liveColor.opacity(0.06), lineWidth: 4).padding(-2).opacity(live ? 1 : 0))
            .overlay(
                shape.fill(LinearGradient(
                    stops: [
                        .init(color: liveColor.opacity(0.10), location: 0),
                        .init(color: liveColor.opacity(0.03), location: 0.6),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
                .allowsHitTesting(false)
                .opacity(live ? 1 : 0)
            )
            .overlay(shape.strokeBorder(live ? liveColor.opacity(0.30) : Theme.Colors.tint(0.10), lineWidth: 1))
            .animation(.easeOut(duration: 0.18), value: live)
    }
}

/// Voice: description and hold key, meter well, chips, then model, language, microphone and shortcut rows.
struct VoiceToolView: View {
    let state: ShellState
    let actions: MenuPanelActions

    static let toolID = "voice"
    /// Notify is left out on purpose: the pill already says what happened. The recorder uses it.
    static let chips: [OutputAction] = [.paste, .copy, .history]

    var body: some View {
        ToolCard(live: state.isListening, liveColor: Theme.Colors.accent) {
            HStack(spacing: 12) {
                VoiceTile()
                Text("Hold to talk, release to paste")
                    .font(.dp(12))
                    .foregroundStyle(Theme.Colors.textSecondary)
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
            options
        }
        .onChange(of: state.isListening) { _, listening in
            if !listening { state.panelMeter.reset() }
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
                OptionRow("Model", detail: state.voiceModelStatus) {
                    HStack(spacing: 8) {
                        if state.voiceEngineID == "apple", state.parakeetDownloaded {
                            RowButton("Remove download") { actions.removeVoiceModel() }
                                .help("Deletes the Parakeet files; selecting Parakeet again downloads them")
                        }
                        PopupPicker(
                            id: "voice.model",
                            selection: Binding(get: { state.voiceEngineID }, set: { actions.setVoiceEngine($0) }),
                            options: state.voiceEngines.map(\.id),
                            title: { id in state.voiceEngines.first { $0.id == id }?.name ?? id },
                            detail: { id in state.voiceEngines.first { $0.id == id }?.detail }
                        )
                    }
                }
                OptionRow("Language") {
                    PopupPicker(
                        id: "voice.language",
                        selection: Binding(get: { state.voiceLanguage }, set: { actions.setVoiceLanguage($0) }),
                        options: state.voiceLanguages,
                        title: { VoiceTool.languageName($0) },
                        detail: { $0.uppercased() }
                    )
                }
                OptionRow("Microphone") {
                    PopupPicker(
                        id: "voice.microphone",
                        selection: Binding(get: { state.voiceMicrophoneUID ?? "" }, set: { actions.setVoiceMicrophone($0.isEmpty ? nil : $0) }),
                        options: [""] + state.microphones.map(\.uid),
                        title: { uid in uid.isEmpty ? "System default" : (state.microphones.first { $0.uid == uid }?.name ?? "Unavailable") }
                    )
                }
                OptionRow("Shortcut") {
                    ShortcutRecorder(.hold(state.holdKey)) { kind in
                        if case .hold(let key) = kind { actions.setHoldKey(key) }
                    }
                }
            }
            .padding(.top, 4)
        }
    }
}

/// Screen: description and combo, chips, then folder, quality, frame rate, audio and shortcut rows.
struct ScreenToolView: View {
    let state: ShellState
    let actions: MenuPanelActions

    static let toolID = "screen"
    static let chips: [OutputAction] = [.saveToFolder, .copy, .revealInFinder, .notify, .history]

    /// "Copy" reads as "Copy file" here; the other labels are shared.
    static func label(_ action: OutputAction) -> String {
        action == .copy ? "Copy file" : action.label
    }

    private var isRecording: Bool {
        if case .recording = state.activity { return true }
        return false
    }

    var body: some View {
        ToolCard(live: isRecording, liveColor: Theme.Colors.record) {
            HStack(spacing: 12) {
                ScreenTile()
                VStack(alignment: .leading, spacing: 2) {
                    Text(isRecording ? "Recording · \(state.screenKey.display) or the menubar stops" : "Region, window or screen")
                        .font(.dp(12))
                        .foregroundStyle(isRecording ? Theme.Colors.record : Theme.Colors.textSecondary)
                        .lineLimit(1)
                    Text(state.screenStatus)
                        .font(.dp(11))
                        .foregroundStyle(Theme.Colors.textFaint)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                HStack(spacing: 4) {
                    ForEach(Array(state.screenKey.symbols.enumerated()), id: \.offset) { _, symbol in
                        Keycap(symbol)
                    }
                }
                .opacity(state.screenKeyTaken ? 0.4 : 1)
                .help(state.screenKeyTaken ? "Another app owns this shortcut" : "Opens the picker")
            }
            chipRow
            options
        }
    }

    private var chipRow: some View {
        let enabled = state.output.config(for: Self.toolID).actions
        return FlowLayout(spacing: 6) {
            ForEach(Self.chips, id: \.self) { action in
                Chip(Self.label(action), isOn: enabled.contains(action)) {
                    actions.toggleOutput(Self.toolID, action)
                }
            }
        }
    }

    private var folderLabel: String {
        let url = state.screenFolder ?? OutputPipeline.defaultFolder
        return url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    private var options: some View {
        VStack(spacing: 0) {
            RowDivider()
            OptionRows {
                OptionRow("Save to") {
                    HStack(spacing: 8) {
                        Text(folderLabel)
                            .font(.dp(11))
                            .foregroundStyle(Theme.Colors.textTertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: 170, alignment: .trailing)
                        RowButton("Choose…") { actions.chooseFolder() }
                    }
                }
                OptionRow("Quality") {
                    PopupPicker(
                        id: "screen.quality",
                        selection: Binding(get: { state.recorderSettings.quality }, set: { value in actions.updateRecorder { $0.quality = value } }),
                        options: RecorderSettings.Quality.allCases,
                        title: { $0.label }
                    )
                }
                OptionRow("Frame rate") {
                    PopupPicker(
                        id: "screen.fps",
                        selection: Binding(get: { state.recorderSettings.frameRate }, set: { value in actions.updateRecorder { $0.frameRate = value } }),
                        options: RecorderSettings.frameRates,
                        title: { "\($0) fps" }
                    )
                }
                OptionRow("System audio") {
                    ToggleSwitch("System audio", isOn: Binding(get: { state.recorderSettings.systemAudio }, set: { value in actions.updateRecorder { $0.systemAudio = value } }))
                }
                OptionRow("Microphone") {
                    ToggleSwitch("Microphone", isOn: Binding(get: { state.recorderSettings.microphone }, set: { value in actions.updateRecorder { $0.microphone = value } }))
                }
                OptionRow("Shortcut") {
                    ShortcutRecorder(.press(state.screenKey)) { kind in
                        if case .press(let combo) = kind { actions.setPressKey(combo) }
                    }
                }
            }
            .padding(.top, 4)
        }
    }
}

/// General view: back chevron, then three groups (app, history, about).
struct GeneralView: View {
    let state: ShellState
    let actions: MenuPanelActions

    var body: some View {
        VStack(spacing: 16) {
            header
            OptionsGroup {
                OptionRow("Launch at login") {
                    ToggleSwitch("Launch at login", isOn: Binding(get: { state.general.launchAtLogin }, set: { actions.setLaunchAtLogin($0) }))
                }
                OptionRow("Sounds", detail: "Start and stop cues") {
                    ToggleSwitch("Sounds", isOn: Binding(get: { state.general.sounds }, set: { state.general.sounds = $0 }))
                }
                OptionRow("Show timer in menubar", detail: "While recording") {
                    ToggleSwitch("Show timer in menubar", isOn: Binding(get: { state.general.menubarTimer }, set: { state.general.menubarTimer = $0 }))
                }
                OptionRow("Pill position", detail: "Listening and recording") {
                    PopupPicker(
                        id: "general.pill",
                        selection: Binding(get: { state.general.pillPosition }, set: { actions.setPillPosition($0) }),
                        options: PillPosition.allCases,
                        title: { $0 == .top ? "Top" : "Bottom" },
                        detail: { $0 == .top ? "under the menubar" : "above the Dock" }
                    )
                }
            }
            OptionsGroup {
                OptionRow("Keep history", detail: historyDetail) {
                    ToggleSwitch("Keep history", isOn: Binding(get: { state.general.keepHistory }, set: { state.general.keepHistory = $0 }))
                }
                OptionRow("Transcripts in history", detail: "Off keeps only recordings") {
                    ToggleSwitch("Transcripts in history", isOn: Binding(
                        get: { state.output.config(for: VoiceToolView.toolID).actions.contains(.history) },
                        set: { _ in actions.toggleOutput(VoiceToolView.toolID, .history) }
                    ))
                }
                OptionRow("Clear history", detail: state.confirmingClear ? "Removes the log, keeps the files" : nil) {
                    if state.confirmingClear {
                        HStack(spacing: 6) {
                            RowButton("Keep") { state.confirmingClear = false }
                            Button {
                                state.confirmingClear = false
                                actions.clearHistory()
                            } label: {
                                Text("Clear \(state.historyCount)")
                                    .font(.dp(12, .medium))
                                    .foregroundStyle(Theme.Colors.bg)
                                    .padding(.horizontal, 10)
                                    .frame(height: 26)
                                    .background(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous).fill(Theme.Colors.record))
                            }
                            .buttonStyle(.plain)
                        }
                    } else {
                        RowButton("Clear…", enabled: state.historyCount > 0) { state.confirmingClear = true }
                    }
                }
            }
            OptionsGroup {
                OptionRow("Permissions") {
                    Button(action: actions.openPermissionSettings) {
                        HStack(spacing: 6) {
                            if state.permissions.allGranted {
                                CheckIcon().stroke(style: .icon(2.4)).frame(width: 10, height: 10)
                            } else {
                                Circle().fill(Theme.Colors.record).frame(width: 6, height: 6)
                            }
                            Text(state.permissions.summary).font(.dp(12))
                        }
                        .foregroundStyle(state.permissions.allGranted ? Theme.Colors.ok : Theme.Colors.record)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(state.permissions.allGranted ? "All granted" : "Open System Settings")
                }
                OptionRow("Version") {
                    HStack(spacing: 8) {
                        Text(state.version).font(.dp(11)).foregroundStyle(Theme.Colors.textTertiary)
                        RowButton("Check for updates", enabled: false) {}
                            .help("Updates arrive with signed builds")
                    }
                }
            }
        }
    }

    private var historyDetail: String {
        let items = state.historyCount == 1 ? "1 item" : "\(state.historyCount) items"
        guard state.historyBytes > 0 else { return items }
        return "\(items) · \(ByteCountFormatter.string(fromByteCount: state.historyBytes, countStyle: .file))"
    }

    private var header: some View {
        SubviewHeader(title: "General", state: state) {
            state.popups.close()
            state.confirmingClear = false
            state.panelView = .main
        }
    }
}

/// "Recent" label, total count, then one row per item (newest first). Times refresh every half minute while open.
struct RecentSection: View {
    let items: [HistoryItem]
    let count: Int
    let thumbnails: ThumbnailCache
    let copy: @MainActor (HistoryItem) -> Void
    let reveal: @MainActor (HistoryItem) -> Void
    let openHistory: @MainActor () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Recent")
                    .font(.dp(11, .semibold))
                    .tracking(0.66)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.Colors.textTertiary)
                Spacer()
                Button(action: openHistory) {
                    HStack(spacing: 4) {
                        Text("All \(count)")
                        ChevronIcon()
                            .stroke(style: .icon(1.4))
                            .rotationEffect(.degrees(-90))
                            .frame(width: 10, height: 10)
                    }
                    .font(.dp(11))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Everything logged, with search")
            }
            .padding(.horizontal, 4)
            TimelineView(.periodic(from: .now, by: 30)) { context in
                ForEach(items) { item in
                    RecentRow(item: item, now: context.date, thumbnails: thumbnails, copy: { copy(item) }, reveal: { reveal(item) })
                }
            }
        }
    }
}

/// Everything logged: search, All / Voice / Recordings, rows grouped by day, "Show older". Scrolls inside the panel.
struct HistoryView: View {
    let state: ShellState
    let actions: MenuPanelActions

    /// Rows per page; `loadHistory(true)` appends another.
    static let pageSize = 20

    var body: some View {
        VStack(spacing: 16) {
            header
            VStack(spacing: 8) {
                SearchField(text: Binding(get: { state.historyQuery }, set: { state.historyQuery = $0 }))
                HStack {
                    Segmented(selection: Binding(get: { state.historyFilter }, set: { value in
                        state.historyFilter = value
                        actions.loadHistory(false)
                    }), options: ShellState.HistoryFilter.allCases, title: { $0.label })
                    Spacer()
                }
            }
            ScrollView(.vertical) {
                LazyVStack(spacing: 16) {
                    if state.historyItems.isEmpty {
                        Text(state.historyQuery.isEmpty ? "Nothing logged yet" : "No matches")
                            .font(.dp(12))
                            .foregroundStyle(Theme.Colors.textTertiary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 60)
                    }
                    ForEach(DayGroup.sections(state.historyItems, date: \.createdAt)) { section in
                        VStack(spacing: 8) {
                            HStack {
                                Text(section.label)
                                    .font(.dp(11, .semibold))
                                    .tracking(0.66)
                                    .textCase(.uppercase)
                                    .foregroundStyle(Theme.Colors.textTertiary)
                                Spacer()
                            }
                            .padding(.horizontal, 4)
                            ForEach(section.items) { item in
                                HistoryRow(item: item, thumbnails: state.thumbnails,
                                           copy: { actions.copyRecent(item) }, reveal: { actions.revealRecent(item) },
                                           delete: { actions.deleteHistory(item) })
                            }
                        }
                    }
                    if state.historyItems.count < state.historyMatches {
                        Button { actions.loadHistory(true) } label: {
                            Text("Show older · \(state.historyMatches - state.historyItems.count) more")
                                .font(.dp(12))
                                .foregroundStyle(Theme.Colors.textSecondary)
                                .frame(maxWidth: .infinity)
                                .frame(height: 32)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, 4)
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: max(200, state.panelMaxHeight - 200))
        }
        // Each query is a table scan on the main actor; wait for a pause in typing instead of scanning per key.
        .task(id: state.historyQuery) {
            do {
                try await Task.sleep(for: .milliseconds(150))
            } catch {
                return
            }
            actions.loadHistory(false)
        }
    }

    private var header: some View {
        HStack {
            Button {
                state.popups.close()
                state.panelView = .main
            } label: {
                HStack(spacing: 8) {
                    ChevronIcon()
                        .stroke(style: .icon(1.6))
                        .rotationEffect(.degrees(90))
                        .foregroundStyle(Theme.Colors.text.opacity(0.7))
                        .frame(width: 12, height: 12)
                        .frame(width: 24, height: 24)
                        .background(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous).fill(Theme.Colors.tint(0.06)))
                        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous).strokeBorder(Theme.Colors.tint(0.12), lineWidth: 1))
                    Text("History")
                        .font(.dp(15, .semibold))
                        .tracking(-0.15)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Back")
            Spacer()
            Text(summary)
                .font(.dp(11))
                .foregroundStyle(Theme.Colors.textTertiary)
        }
    }

    private var summary: String {
        let items = state.historyCount == 1 ? "1 item" : "\(state.historyCount) items"
        guard state.historyBytes > 0 else { return items }
        return "\(items) · \(ByteCountFormatter.string(fromByteCount: state.historyBytes, countStyle: .file))"
    }
}

/// A History row: like a Recent row, with the clock time instead of a relative one and a delete button on hover.
struct HistoryRow: View {
    let item: HistoryItem
    let thumbnails: ThumbnailCache
    let copy: @MainActor () -> Void
    let reveal: @MainActor () -> Void
    let delete: @MainActor () -> Void
    @State private var hovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
        HStack(spacing: hovering ? 8 : 12) {
            HistoryTile(item: item, thumbnails: thumbnails)
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
            if item.text != nil {
                RowActionButton("Copy transcript", icon: CopyIcon(), action: copy)
            } else {
                RowActionButton("Show in Finder", icon: FolderIcon(), action: reveal)
            }
            if hovering {
                Button(action: delete) {
                    TrashIcon()
                        .stroke(style: .icon(1.5))
                        .foregroundStyle(Theme.Colors.record.opacity(0.85))
                        .frame(width: 14, height: 14)
                        .frame(width: 28, height: 28)
                        .background(RoundedRectangle(cornerRadius: Theme.Radius.keycap, style: .continuous).fill(Theme.Colors.tint(0.05)))
                        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.keycap, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("Remove from history (keeps the file)")
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 10)
        .background(shape.fill(Theme.Colors.tint(hovering ? 0.06 : 0.03)))
        .overlay(shape.strokeBorder(Theme.Colors.tint(hovering ? 0.12 : 0.07), lineWidth: 1))
        .contentShape(shape)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .onTapGesture(count: 2) {
            if item.fileURL != nil { reveal() }
        }
        // The trash button only appears on hover and reveal is a double-click, so both are also row actions
        // for VoiceOver and keyboard users.
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: "Remove from history") { delete() }
        .accessibilityActions {
            if item.fileURL != nil {
                Button("Show in Finder") { reveal() }
            }
        }
    }

    private var title: String {
        if let text = item.text, !text.isEmpty { return text }
        return item.fileURL?.lastPathComponent ?? "Capture"
    }

    private var meta: String {
        var parts = [DayGroup.clock(item.createdAt)]
        if let duration = item.duration, item.text == nil {
            parts.append(TimeFormat.minutesSeconds(duration))
        }
        if let target = item.pastedInto {
            parts.append("pasted into \(target)")
        } else if item.fileURL != nil {
            parts.append(FileManager.default.fileExists(atPath: item.fileURL?.path ?? "") ? "saved" : "file missing")
        } else {
            parts.append("copied")
        }
        return parts.joined(separator: " · ")
    }
}

/// The 44x30 tile shared by Recent and History rows.
struct HistoryTile: View {
    let item: HistoryItem
    let thumbnails: ThumbnailCache

    var body: some View {
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
            // File capture: a frame from the file, dark placeholder until it loads or when the file is gone.
            ZStack(alignment: .bottomTrailing) {
                shape.fill(LinearGradient(colors: [Color(hex: 0x3B42_52), Color(hex: 0x2226_2F)], startPoint: .topLeading, endPoint: .bottomTrailing))
                if let file = item.fileURL, let frame = thumbnails.image(for: file) {
                    Image(decorative: frame, scale: 2)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 44, height: 30)
                        .clipShape(shape)
                        .transition(.opacity)
                }
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
            .animation(.easeOut(duration: 0.2), value: item.fileURL.flatMap { thumbnails.image(for: $0) } != nil)
        }
    }
}

struct RecentRow: View {
    let item: HistoryItem
    let now: Date
    let thumbnails: ThumbnailCache
    let copy: @MainActor () -> Void
    let reveal: @MainActor () -> Void

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
            RowActionButton(item.text != nil ? "Copy transcript" : "Copy file", icon: CopyIcon(), action: copy)
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 10)
        .background(shape.fill(Theme.Colors.tint(0.03)))
        .overlay(shape.strokeBorder(Theme.Colors.tint(0.07), lineWidth: 1))
        .contentShape(shape)
        .onTapGesture(count: 2) {
            if item.fileURL != nil { reveal() }
        }
        .help(item.fileURL != nil ? "Double-click to show in Finder" : "")
        .accessibilityElement(children: .combine)
        .accessibilityActions {
            if item.fileURL != nil {
                Button("Show in Finder") { reveal() }
            }
        }
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

    private var tile: some View {
        HistoryTile(item: item, thumbnails: thumbnails)
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
