import DeskpouchCapture
import DeskpouchCore
import SwiftUI
import ToolScreenRecorder
import ToolScreenshot
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
            ToolsSection(state: state) {
                state.popups.close()
                state.panelView = .general
            }
            if !state.recent.isEmpty {
                RecentSection(items: state.recent, count: state.historyCount, thumbnails: state.thumbnails,
                              copy: actions.copyRecent, reveal: actions.revealRecent, edit: actions.edit,
                              preview: { actions.openGallery($0) },
                              copyText: actions.copyText, expandedColor: state.expandedColor,
                              toggleFormats: { state.expandedColor = state.expandedColor == $0.id ? nil : $0.id }) {
                    state.popups.close()
                    actions.openGallery(nil)
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

/// "Tools" label, count, then one row per switched-on tool.
struct ToolsSection: View {
    let state: ShellState
    let openGeneral: @MainActor () -> Void

    var body: some View {
        let tools = PanelTools.enabled(in: state)
        VStack(spacing: 6) {
            HStack {
                Text("Tools")
                    .font(.dp(11, .semibold))
                    .tracking(0.66)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.Colors.textTertiary)
                Spacer()
                Text("\(tools.count)")
                    .font(.dp(11))
                    .foregroundStyle(Theme.Colors.textFaint)
            }
            .padding(.horizontal, 4)
            ForEach(tools) { tool in
                tool.row(state)
            }
            if tools.isEmpty {
                Button(action: openGeneral) {
                    Text("Every tool is off. Switch one on in General.")
                        .font(.dp(12))
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                                .strokeBorder(Theme.Colors.tint(0.10), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// A tool's row on the main view: tile, name, one-line status, shortcut keycaps, chevron. Amber while listening,
/// pink while recording.
struct ToolRow<Tile: View, Status: View, Keys: View>: View {
    /// Amber while listening (or an event minutes away), pink while recording, mint while an event runs.
    enum Live { case none, listening, recording, ok }

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
        switch live {
        case .recording: Theme.Colors.record
        case .ok: Theme.Colors.ok
        default: Theme.Colors.accent
        }
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

struct ScreenshotRow: View {
    let state: ShellState

    var body: some View {
        ToolRow(name: "Screenshot", live: .none, open: { state.panelView = .tool(ScreenshotToolView.toolID) }) {
            ScreenshotTile()
        } status: {
            Text("\(state.shotSettings.scale.label(nativeScale: state.mainScreenScale)) · \(shotFolderName)")
                .foregroundStyle(Theme.Colors.textTertiary)
        } keys: {
            ForEach(Array(state.shotKey.symbols.enumerated()), id: \.offset) { _, symbol in
                Keycap(symbol)
            }
        }
        .opacity(state.shotKeyTaken ? 0.7 : 1)
    }

    /// "Pictures/Deskpouch" for the row status, home-relative with no leading tilde.
    private var shotFolderName: String {
        let url = state.shotFolder ?? ScreenshotTool.defaultFolder
        return url.path.replacingOccurrences(of: NSHomeDirectory() + "/", with: "")
    }
}

/// Amber gradient tile with the mic. 36 in the Tools list, smaller in General's switches.
struct VoiceTile: View {
    var size: CGFloat = 36

    var body: some View {
        let tile = RoundedRectangle(cornerRadius: Theme.Radius.tile * size / 36, style: .continuous)
        MicIcon()
            .stroke(style: .icon(1.7))
            .foregroundStyle(Theme.Colors.accentInk)
            .frame(width: size / 2, height: size / 2)
            .frame(width: size, height: size)
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
            .shadow(color: Theme.Colors.accent(0.35), radius: 8 * size / 36, y: 6 * size / 36)
    }
}

/// Tint tile with the display glyph. 36 in the Tools list, smaller in General's switches.
struct ScreenTile: View {
    var size: CGFloat = 36

    var body: some View {
        let tile = RoundedRectangle(cornerRadius: Theme.Radius.tile * size / 36, style: .continuous)
        ScreenIcon()
            .stroke(style: .icon(1.6))
            .foregroundStyle(Theme.Colors.text)
            .frame(width: size / 2, height: size / 2)
            .frame(width: size, height: size)
            .background(tile.fill(Theme.Colors.tint(0.06)))
            .overlay(tile.strokeBorder(Theme.Colors.tint(0.14), lineWidth: 1))
            .overlay(alignment: .top) {
                Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1)
                    .padding(.horizontal, Theme.Radius.tile).padding(.top, 1)
            }
    }
}

/// Mint tile with the region brackets glyph. 36 in the Tools list, smaller in General's switches.
struct ScreenshotTile: View {
    var size: CGFloat = 36

    var body: some View {
        let tile = RoundedRectangle(cornerRadius: Theme.Radius.tile * size / 36, style: .continuous)
        RegionIcon()
            .stroke(style: .icon(1.6))
            .foregroundStyle(Theme.Colors.ok)
            .frame(width: size / 2, height: size / 2)
            .frame(width: size, height: size)
            .background(tile.fill(Theme.Colors.ok(0.12)))
            .overlay(tile.strokeBorder(Theme.Colors.ok(0.22), lineWidth: 1))
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
            PanelTools.tool(toolID)?.view(state, actions)
        }
    }

    private var title: String {
        PanelTools.tool(toolID)?.name ?? toolID
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

    @State private var editingDictionary = false

    var body: some View {
        ToolCard(live: state.isListening, liveColor: Theme.Colors.accent) {
            HStack(spacing: 12) {
                VoiceTile()
                Text(state.voiceTapToLock ? "Hold to talk, or tap to lock" : "Hold to talk, release to paste")
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
                OptionRow("Tap to lock", detail: "tap the key to talk hands-free, tap again to finish") {
                    ToggleSwitch("Tap to lock", isOn: Binding(get: { state.voiceTapToLock }, set: { actions.setVoiceTapToLock($0) }))
                }
                cleanUp
                OptionRow("Dictionary", detail: dictionaryDetail) {
                    RowButton(editingDictionary ? "Done" : "Edit") { editingDictionary.toggle() }
                }
                if editingDictionary {
                    DictionaryEditor(
                        entries: Binding(get: { state.voiceDictionary }, set: { actions.setVoiceDictionary($0) })
                    )
                }
            }
            .padding(.top, 4)
        }
    }

    private var dictionaryDetail: String {
        let count = state.voiceDictionary.filter(\.isUsable).count
        return count == 0 ? "names and jargon the engine gets wrong" : "\(count) \(count == 1 ? "word" : "words") corrected"
    }

    /// What happens to the text after decode, as chips: they read as one set, like the output chips above.
    private var cleanUp: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Clean-up")
                .font(.dp(10))
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundStyle(Theme.Colors.textTertiary)
            FlowLayout(spacing: 6) {
                Chip("Skip um, uh", isOn: state.voiceSkipFillers) {
                    actions.setVoiceSkipFillers(!state.voiceSkipFillers)
                }
                Chip("Numbers as digits", isOn: state.voiceNumbersAsDigits) {
                    actions.setVoiceNumbersAsDigits(!state.voiceNumbersAsDigits)
                }
                .help("\"two hundred dollars\" becomes \"$200\", \"three thirty pm\" becomes \"3:30 PM\". One to nine stay words. English only.")
                Chip("Spoken punctuation", isOn: state.voiceSpokenPunctuation) {
                    actions.setVoiceSpokenPunctuation(!state.voiceSpokenPunctuation)
                }
                .help("Say \"comma\", \"question mark\", \"new line\" or \"new paragraph\". English commands.")
                Chip("\"Send\" presses Return", isOn: state.voiceSayToSend) {
                    actions.setVoiceSayToSend(!state.voiceSayToSend)
                }
                .help("End a dictation with \"send\" as its own sentence: the text is pasted, then Return is pressed. Needs Paste on; without it the word stays in the text.")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
    }
}

/// The voice dictionary: one line per entry, what the engine writes on the left, what it should write on the right.
/// Typing edits a draft; it is handed over half a second after the last change and when the editor closes, so
/// the tool does not rebuild its rules and rewrite its defaults on every keystroke.
struct DictionaryEditor: View {
    @Binding var entries: [WordReplacement]
    @State private var draft: [WordReplacement] = []
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach($draft) { $entry in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        field("heard", text: $entry.heard)
                        ChevronIcon()
                            .stroke(style: .icon(1.4))
                            .foregroundStyle(Theme.Colors.textTertiary)
                            .frame(width: 8, height: 8)
                        field("written", text: $entry.written)
                        Button {
                            draft.removeAll { $0.id == entry.id }
                        } label: {
                            Text("Remove").font(.dp(11)).foregroundStyle(Theme.Colors.textTertiary)
                        }
                        .buttonStyle(.plain)
                    }
                    if entry.isUsable, entry.written.trimmingCharacters(in: .whitespaces).isEmpty {
                        Text("nothing written: the word is deleted from dictations")
                            .font(.dp(10))
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                }
            }
            RowButton("Add word") { draft.append(WordReplacement(heard: "", written: "")) }
        }
        .padding(.vertical, 10)
        .onAppear {
            draft = entries
            loaded = true
        }
        .task(id: draft) {
            guard loaded, draft != entries else { return }
            try? await Task.sleep(for: .milliseconds(500))
            if !Task.isCancelled { commit() }
        }
        .onDisappear { commit() }
    }

    private func commit() {
        if loaded, draft != entries { entries = draft }
    }

    private func field(_ placeholder: String, text: Binding<String>) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
        return TextField(placeholder, text: text)
            .textFieldStyle(.plain)
            .font(.dp(12))
            .foregroundStyle(Theme.Colors.text)
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(shape.fill(Theme.Colors.well))
            .overlay(shape.strokeBorder(Theme.Colors.tint(0.08), lineWidth: 1))
            .onSubmit { commit() }
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

/// Screenshot: description and combo, chips, then scale, folder, window shadow and shortcut rows. Annotate is
/// reached from the pill and from the hover button on screenshot rows, not from this card.
struct ScreenshotToolView: View {
    let state: ShellState
    let actions: MenuPanelActions

    static let toolID = "screenshot"
    static let chips: [OutputAction] = [.copy, .saveToFolder, .revealInFinder, .history]

    /// "Copy" reads as "Copy image" here; the other labels are shared.
    static func label(_ action: OutputAction) -> String {
        action == .copy ? "Copy image" : action.label
    }

    var body: some View {
        ToolCard(live: false, liveColor: Theme.Colors.ok) {
            HStack(spacing: 12) {
                ScreenshotTile()
                Text("Region, window or screen")
                    .font(.dp(12))
                    .foregroundStyle(Theme.Colors.textSecondary)
                Spacer(minLength: 8)
                HStack(spacing: 4) {
                    ForEach(Array(state.shotKey.symbols.enumerated()), id: \.offset) { _, symbol in
                        Keycap(symbol)
                    }
                }
                .opacity(state.shotKeyTaken ? 0.4 : 1)
                .help(state.shotKeyTaken ? "Another app owns this shortcut" : "Opens the picker")
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
        let url = state.shotFolder ?? ScreenshotTool.defaultFolder
        return url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    private var options: some View {
        VStack(spacing: 0) {
            RowDivider()
            OptionRows {
                OptionRow("Scale") {
                    PopupPicker(
                        id: "shot.scale",
                        selection: Binding(get: { state.shotSettings.scale }, set: { value in actions.updateScreenshot { $0.scale = value } }),
                        options: CaptureScale.allCases,
                        title: { $0.label(nativeScale: state.mainScreenScale) }
                    )
                }
                OptionRow("Save to") {
                    HStack(spacing: 8) {
                        Text(folderLabel)
                            .font(.dp(11))
                            .foregroundStyle(Theme.Colors.textTertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: 170, alignment: .trailing)
                        RowButton("Choose…") { actions.chooseScreenshotFolder() }
                    }
                }
                OptionRow("Window shadow") {
                    ToggleSwitch("Window shadow", isOn: Binding(get: { state.shotSettings.windowShadow }, set: { value in actions.updateScreenshot { $0.windowShadow = value } }))
                }
                OptionRow("Shortcut") {
                    ShortcutRecorder(.press(state.shotKey)) { kind in
                        if case .press(let combo) = kind { actions.setShotPressKey(combo) }
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
                ForEach(PanelTools.all) { tool in
                    ToolSwitchRow(tool: tool, isOn: Binding(
                        get: { state.switches.isEnabled(tool.id) },
                        set: { actions.setToolEnabled(tool.id, $0) }
                    ))
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

/// A General row that switches one tool on or off: small tile, name, switch. Off hides the tool's row and frees
/// its shortcut; its history stays.
struct ToolSwitchRow: View {
    let tool: PanelTool
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 10) {
            tool.tile(24)
                .opacity(isOn ? 1 : 0.5)
            Text(tool.name).font(.dp(13)).foregroundStyle(Theme.Colors.text)
            Spacer(minLength: 8)
            ToggleSwitch(tool.name, isOn: $isOn)
        }
        .frame(height: 40)
    }
}

/// "Recent" label, total count, then one row per item (newest first). Times refresh every half minute while open.
struct RecentSection: View {
    let items: [HistoryItem]
    let count: Int
    let thumbnails: ThumbnailCache
    let copy: @MainActor (HistoryItem) -> Void
    let reveal: @MainActor (HistoryItem) -> Void
    let edit: @MainActor (HistoryItem) -> Void
    /// Opens the gallery on the row.
    let preview: @MainActor (HistoryItem) -> Void
    /// Copies one of the formats under an expanded colour row.
    let copyText: @MainActor (String) -> Void
    /// The colour row showing its formats, and the toggle for it.
    let expandedColor: UUID?
    let toggleFormats: @MainActor (HistoryItem) -> Void
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
                .help("The gallery: everything captured, with search and previews")
            }
            .padding(.horizontal, 4)
            TimelineView(.periodic(from: .now, by: 30)) { context in
                ForEach(items) { item in
                    RecentRow(item: item, now: context.date, thumbnails: thumbnails, copy: { copy(item) }, reveal: { reveal(item) },
                              edit: editAction(item), preview: { preview(item) }, copyText: copyText,
                              showingFormats: expandedColor == item.id, toggleFormats: { toggleFormats(item) })
                }
            }
        }
    }
}

extension RecentSection {
    func editAction(_ item: HistoryItem) -> (@MainActor () -> Void)? {
        guard item.editLabel != nil else { return nil }
        return { edit(item) }
    }
}

/// The 44x30 tile of a Recent row.
struct HistoryTile: View {
    let item: HistoryItem
    let thumbnails: ThumbnailCache

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
        if item.kind == .color {
            ColorSwatchTile(color: item.pickedColor)
        } else if item.text != nil {
            MicIcon()
                .stroke(style: .icon(1.7))
                .foregroundStyle(Theme.Colors.accentHigh)
                .frame(width: 14, height: 14)
                .frame(width: 44, height: 30)
                .background(shape.fill(Theme.Colors.accent(0.14)))
                .overlay(shape.strokeBorder(Theme.Colors.accent(0.25), lineWidth: 1))
        } else {
            // File capture: a frame from a recording, or a screenshot's cached JPEG thumbnail; dark placeholder
            // until it loads or when the source is gone.
            ZStack(alignment: .bottomTrailing) {
                shape.fill(LinearGradient(colors: [Color(hex: 0x3B42_52), Color(hex: 0x2226_2F)], startPoint: .topLeading, endPoint: .bottomTrailing))
                if let url = thumbnailURL, let frame = thumbnails.image(for: url) {
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
            .animation(.easeOut(duration: 0.2), value: thumbnailURL.flatMap { thumbnails.image(for: $0) } != nil)
        }
    }

    /// The thumbnail JPEG for an image result (kept small, decoded straight away), or the file itself for a
    /// recording (a frame is generated from the video on demand). Screenshots without one yet (an older row from
    /// before thumbnails existed) fall back to the PNG itself.
    private var thumbnailURL: URL? {
        item.kind == .screenshot ? (item.thumbURL ?? item.fileURL) : item.fileURL
    }
}

struct RecentRow: View {
    let item: HistoryItem
    let now: Date
    let thumbnails: ThumbnailCache
    let copy: @MainActor () -> Void
    let reveal: @MainActor () -> Void
    let edit: (@MainActor () -> Void)?
    /// Opens the gallery on this row.
    let preview: @MainActor () -> Void
    let copyText: @MainActor (String) -> Void
    let showingFormats: Bool
    let toggleFormats: @MainActor () -> Void
    @State private var hovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
        VStack(spacing: 8) {
        HStack(spacing: hovering ? 8 : 12) {
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
            if hovering {
                if let edit { EditRowButton(item: item, action: edit) }
                RowActionButton("Preview in the gallery", icon: EyeIcon(), action: preview)
            }
            RowActionButton(item.copyLabel, icon: CopyIcon(), action: copy)
            if item.pickedColor != nil {
                FormatsDisclosure(isOpen: showingFormats, action: toggleFormats)
            }
        }
        if showingFormats, let color = item.pickedColor {
            ColorFormatsList(color: color, copy: copyText)
        }
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 10)
        .background(shape.fill(Theme.Colors.tint(hovering ? 0.06 : 0.03)))
        .overlay(shape.strokeBorder(Theme.Colors.tint(hovering ? 0.12 : 0.07), lineWidth: 1))
        .contentShape(shape)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .animation(.easeOut(duration: 0.16), value: showingFormats)
        // One gesture, the click count read off the event: a separate double-tap gesture would hold every single
        // click until the double-click interval is over.
        .onTapGesture {
            if (NSApp.currentEvent?.clickCount ?? 1) >= 2 {
                preview()
            } else if item.pickedColor != nil {
                toggleFormats()
            }
        }
        .contextMenu {
            Button("Preview in the Gallery", action: preview)
            if item.fileURL != nil { Button("Show in Finder", action: reveal) }
        }
        .help(helpText)
        .accessibilityElement(children: .combine)
        .accessibilityActions {
            Button("Preview in the gallery") { preview() }
            if item.fileURL != nil {
                Button("Show in Finder") { reveal() }
            }
            if let edit {
                Button(item.editLabel ?? "Edit") { edit() }
            }
            if item.pickedColor != nil {
                Button(showingFormats ? "Hide the other formats" : "Show every format", action: toggleFormats)
            }
        }
    }

    private var helpText: String {
        if item.pickedColor != nil { return "Click for every format, double-click for the gallery" }
        return "Double-click to preview in the gallery"
    }

    private var title: String {
        if let text = item.text, !text.isEmpty { return text }
        return item.fileURL?.lastPathComponent ?? "Capture"
    }

    private var meta: String {
        var parts = [RelativeTime.phrase(from: item.createdAt, now: now)]
        if let hint = item.tailwindHint {
            parts.append(hint)
        } else if let target = item.pastedInto {
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

/// Hover action on screenshot rows: amber pencil, opens the editor.
struct EditRowButton: View {
    let item: HistoryItem
    let action: @MainActor () -> Void

    var body: some View {
        Button(action: action) {
            (item.canTrim ? AnyShape(TrimIcon()) : AnyShape(PencilIcon()))
                .stroke(style: .icon(1.5))
                .foregroundStyle(Theme.Colors.accentHigh)
                .frame(width: 14, height: 14)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.keycap, style: .continuous).fill(Theme.Colors.accent(0.14)))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.keycap, style: .continuous).strokeBorder(Theme.Colors.accent(0.30), lineWidth: 1))
                .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.keycap, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(item.editLabel ?? "")
        .accessibilityLabel(item.editLabel ?? "")
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
    }
}

extension HistoryItem {
    /// Label on the row's copy button.
    var copyLabel: String {
        switch kind {
        case .color: "Copy value"
        case .screenshot: "Copy image"
        default: text != nil ? "Copy transcript" : "Copy file"
        }
    }

    /// A screenshot whose file is still there.
    var canAnnotate: Bool {
        guard kind == .screenshot, let fileURL else { return false }
        return FileManager.default.fileExists(atPath: fileURL.path)
    }

    /// A recording whose file is still there. Not a GIF: there is nothing left to cut a GIF from cleanly.
    var canTrim: Bool {
        guard kind == .recording, let fileURL, fileURL.pathExtension.lowercased() != "gif" else { return false }
        return FileManager.default.fileExists(atPath: fileURL.path)
    }

    /// What the row's hover button opens: Annotate for a screenshot, Trim for a recording.
    var editLabel: String? {
        if canAnnotate { return "Annotate" }
        if canTrim { return "Trim" }
        return nil
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
