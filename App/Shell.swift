import AppKit
import DeskpouchCore
import ToolScreenRecorder
import ToolVoice
import os

private let log = Logger(subsystem: "com.constantinchirila.deskpouch", category: "shell")

/// Composition root. Owns hotkeys, overlay, output pipeline, status item, the menubar panel and the tools.
@MainActor
final class Shell {
    let state = ShellState()
    private let hotkeys = HotkeyCenter()
    private let overlay = OverlayController()
    private let history: HistoryStore?
    private let pipeline: OutputPipeline
    private let statusItem = StatusItemController()
    private lazy var panel = MenuPanelController(state: state, actions: panelActions)

    private let voice = VoiceTool()
    private let screen = ScreenRecorderTool()
    private var tools: [Tool] { [voice, screen] }

    private var permissionPoll: Timer?
    private var recordingTimer: Timer?
    private var holdRegistrations: [String: HotkeyCenter.Registration] = [:]
    private var pressRegistrations: [String: HotkeyCenter.PressRegistration] = [:]

    static let recentLimit = 5

    init() {
        do {
            history = try HistoryStore(url: HistoryStore.defaultURL)
        } catch {
            log.error("history unavailable: \(String(describing: error), privacy: .public)")
            history = nil
        }
        pipeline = OutputPipeline(effects: SystemOutputEffects(), history: history)
    }

    func start() {
        let context = ToolContext(
            overlay: overlay,
            emit: { [weak self] result in self?.deliver(result) },
            activity: { [weak self] _, activity in self?.activityChanged(activity) }
        )
        for tool in tools {
            state.output.registerDefault(tool.defaultOutput, for: tool.id)
            tool.attach(context)
            registerPress(tool)
            registerHold(tool)
        }
        overlay.onLevel = { [weak self] level, dt in
            // The meter timer can tick once more between the key release and the transcription task stopping it;
            // that tick must not paint the meter back over the idle icon.
            guard let self, state.isListening else { return }
            statusItem.push(level: level, dt: dt)
            state.panelMeter.push(level: level, dt: dt)
        }
        voice.onStatus = { [weak self] text in
            self?.state.voiceStatus = text
        }
        overlay.position = state.general.pillPosition
        state.holdKey = voice.holdKey ?? .rightOption
        state.screenKey = screen.pressKey ?? .commandShift6
        state.screenStatus = screen.settings.summary
        state.recorderSettings = screen.settings
        state.screenFolder = state.output.config(for: screen.id).folder
        state.voiceEngine = voice.engineName
        state.voiceLanguage = voice.language
        state.voiceLanguages = voice.supportedLanguages
        state.voiceMicrophoneUID = voice.microphoneUID
        state.voiceSkipFillers = voice.skipFillers
        screen.onStatus = { [weak self] text in
            guard let self else { return }
            state.screenStatus = text
            state.recorderSettings = screen.settings
        }
        statusItem.onClick = { [weak self] button in
            guard let self else { return }
            // While recording the icon is the stop button; the panel is not reachable until the recording ends.
            if screen.isRecording {
                screen.stopRecording()
            } else {
                if !panel.isVisible { refreshPanelInfo() }
                panel.toggle(relativeTo: button)
            }
        }
        statusItem.showIdle()
        refreshRecent()
        startHotkeysOrWait()
        voice.warmUp()
        runDemoIfRequested()
    }

    func stop() {
        hotkeys.stop()
        permissionPoll?.invalidate()
        recordingTimer?.invalidate()
    }

    // MARK: Hotkeys

    private func registerHold(_ tool: Tool) {
        if let old = holdRegistrations.removeValue(forKey: tool.id) { hotkeys.unregister(old) }
        guard let key = tool.holdKey else { return }
        holdRegistrations[tool.id] = hotkeys.registerHold(key) { [weak self, weak tool] phase in
            guard let self, let tool else { return }
            switch phase {
            case .pressed:
                state.isListening = true
                statusItem.beginListening()
                playCue(start: true)
                tool.holdBegan()
            case .released:
                state.isListening = false
                statusItem.showIdle()
                playCue(start: false)
                tool.holdEnded()
            }
        }
    }

    private func registerPress(_ tool: Tool) {
        if let old = pressRegistrations.removeValue(forKey: tool.id) { hotkeys.unregister(old) }
        guard let combo = tool.pressKey else { return }
        if let registration = hotkeys.registerPress(combo, handler: { [weak tool] in tool?.keyPressed() }) {
            pressRegistrations[tool.id] = registration
            if tool.id == screen.id { state.screenKeyTaken = false }
        } else {
            log.error("\(combo.display, privacy: .public) is taken by another app")
            if tool.id == screen.id { state.screenKeyTaken = true }
        }
    }

    private func setHoldKey(_ key: ModifierKey) {
        voice.holdKey = key
        state.holdKey = key
        registerHold(voice)
    }

    private func setPressKey(_ combo: KeyCombo) {
        screen.pressKey = combo
        state.screenKey = combo
        registerPress(screen)
    }

    // MARK: Activity

    private func activityChanged(_ activity: ToolActivity) {
        state.activity = activity
        recordingTimer?.invalidate()
        recordingTimer = nil
        switch activity {
        case .idle:
            statusItem.showIdle()
            playCue(start: false)
        case .recording(let since):
            panel.close()
            playCue(start: true)
            showRecordingIcon(since: since)
            recordingTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.showRecordingIcon(since: since) }
            }
        }
    }

    private func showRecordingIcon(since: Date) {
        statusItem.showRecording(elapsed: state.general.menubarTimer ? Date().timeIntervalSince(since) : nil)
    }

    /// Start and stop cues, system sounds so nothing has to ship.
    private func playCue(start: Bool) {
        guard state.general.sounds else { return }
        NSSound(named: start ? "Tink" : "Pop")?.play()
    }

    // MARK: Panel info

    /// Things that can change behind the panel's back: permissions, model download, microphones, history size.
    private func refreshPanelInfo() {
        state.permissions = PermissionStatus(
            microphone: Permissions.microphone == .granted,
            screenRecording: Permissions.screenRecordingGranted,
            accessibility: Permissions.accessibilityGranted
        )
        state.general.refreshLaunchAtLogin()
        state.voiceModelStatus = voice.modelStatus
        state.microphones = AudioInputDevices.all()
        refreshRecent()
    }

    private func chooseFolder() {
        let open = NSOpenPanel()
        open.canChooseDirectories = true
        open.canChooseFiles = false
        open.canCreateDirectories = true
        open.directoryURL = state.screenFolder ?? OutputPipeline.defaultFolder
        open.prompt = "Use folder"
        open.message = "Recordings are saved here"
        panel.holdsOpen = true
        NSApp.activate()
        open.begin { [weak self] response in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.panel.holdsOpen = false
                guard response == .OK, let url = open.url else { return }
                self.state.output.update(self.screen.id) { $0.folder = url }
                self.state.screenFolder = url
            }
        }
    }

    /// Loads the first page for the current query and filter, or appends the next one.
    private func loadHistory(more: Bool) {
        guard let history else { return }
        let query = state.historyQuery.trimmingCharacters(in: .whitespaces)
        let toolID = state.historyFilter.toolID
        do {
            let offset = more ? state.historyItems.count : 0
            let page = try history.items(matching: query, toolID: toolID, limit: HistoryView.pageSize, offset: offset)
            state.historyItems = more ? state.historyItems + page : page
            state.historyMatches = try history.count(matching: query, toolID: toolID)
        } catch {
            log.error("history query failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func deleteHistory(_ item: HistoryItem) {
        guard let history else { return }
        do {
            try history.delete(id: item.id)
        } catch {
            log.error("history delete failed: \(String(describing: error), privacy: .public)")
            return
        }
        state.historyItems.removeAll { $0.id == item.id }
        state.historyMatches = max(0, state.historyMatches - 1)
        refreshRecent()
    }

    private func clearHistory() {
        guard let history else { return }
        do {
            try history.clear()
        } catch {
            log.error("clear history failed: \(String(describing: error), privacy: .public)")
        }
        refreshRecent()
    }

    private func openPermissionSettings() {
        let p = state.permissions
        if !p.accessibility {
            Permissions.requestAccessibility()
            Permissions.openAccessibilitySettings()
        } else if !p.screenRecording {
            Permissions.requestScreenRecording()
            Permissions.openScreenRecordingSettings()
        } else if !p.microphone {
            Permissions.openMicrophoneSettings()
        } else {
            Permissions.openAccessibilitySettings()
        }
    }

    // MARK: Output

    private func deliver(_ result: ToolResult) {
        Task { [weak self] in
            guard let self else { return }
            var config = state.output.config(for: result.toolID)
            if !state.general.keepHistory { config.actions.remove(.history) }
            let delivery = await pipeline.deliver(result, config: config)
            if let target = delivery.pastedInto {
                overlay.flash(.pasted(target: target))
            } else if let saved = delivery.savedTo {
                overlay.flash(.saved(name: saved.lastPathComponent, copied: delivery.copied), for: .seconds(2))
            } else if delivery.copied {
                overlay.flash(.copied)
            } else {
                overlay.hide()
            }
            if delivery.recorded { refreshRecent() }
        }
    }

    private func refreshRecent() {
        guard let history else { return }
        do {
            state.recent = try history.recent(limit: Self.recentLimit)
            state.historyCount = try history.count()
            state.historyBytes = try history.filePaths().reduce(into: Int64(0)) { total, path in
                let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber)?.int64Value ?? 0
                total += size
            }
        } catch {
            log.error("history read failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func copyRecent(_ item: HistoryItem) {
        if let text = item.text, !text.isEmpty {
            Paster.copy(text)
        } else if let file = item.fileURL {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([file as NSURL])
        } else {
            return
        }
        overlay.flash(.copied)
    }

    // MARK: Hotkey permission

    private func startHotkeysOrWait() {
        if hotkeys.start() {
            state.hotkeyReady = true
            permissionPoll?.invalidate()
            permissionPoll = nil
            return
        }
        state.hotkeyReady = false
        guard permissionPoll == nil else { return }
        // First failure: show the system Accessibility prompt so the hold key can work at all.
        Permissions.requestAccessibility()
        permissionPoll = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.startHotkeysOrWait() }
        }
    }

    private var panelActions: MenuPanelActions {
        MenuPanelActions(
            requestPermission: { [weak self] in
                guard let self else { return }
                Permissions.requestAccessibility()
                Permissions.openAccessibilitySettings()
                startHotkeysOrWait()
            },
            toggleOutput: { [weak self] toolID, action in
                self?.state.output.toggle(action, for: toolID)
            },
            copyRecent: { [weak self] item in
                self?.copyRecent(item)
            },
            revealRecent: { item in
                guard let file = item.fileURL else { return }
                NSWorkspace.shared.activateFileViewerSelecting([file])
            },
            setHoldKey: { [weak self] key in self?.setHoldKey(key) },
            setPressKey: { [weak self] combo in self?.setPressKey(combo) },
            setVoiceLanguage: { [weak self] code in
                guard let self else { return }
                voice.language = code
                state.voiceLanguage = voice.language
            },
            setVoiceMicrophone: { [weak self] uid in
                guard let self else { return }
                voice.microphoneUID = uid
                state.voiceMicrophoneUID = uid
            },
            setVoiceSkipFillers: { [weak self] on in
                guard let self else { return }
                voice.skipFillers = on
                state.voiceSkipFillers = on
            },
            updateRecorder: { [weak self] change in
                guard let self else { return }
                var settings = screen.settings
                change(&settings)
                screen.settings = settings
                state.recorderSettings = settings
            },
            chooseFolder: { [weak self] in self?.chooseFolder() },
            setLaunchAtLogin: { [weak self] on in self?.state.general.setLaunchAtLogin(on) },
            setPillPosition: { [weak self] position in
                guard let self else { return }
                state.general.pillPosition = position
                overlay.position = position
            },
            clearHistory: { [weak self] in self?.clearHistory() },
            loadHistory: { [weak self] more in self?.loadHistory(more: more) },
            deleteHistory: { [weak self] item in self?.deleteHistory(item) },
            openPermissionSettings: { [weak self] in self?.openPermissionSettings() },
            closePanel: { [weak self] in self?.panel.close() },
            quit: { NSApp.terminate(nil) }
        )
    }

    // MARK: Demo

    /// `DESKPOUCH_DEMO=pill` shows the listening state and the panel for a few seconds at launch.
    /// With `DESKPOUCH_DEMO_OUT=<dir>` it also writes PNGs of both. Design review only.
    private func runDemoIfRequested() {
        let env = ProcessInfo.processInfo.environment
        let out = env["DESKPOUCH_DEMO_OUT"].map { URL(fileURLWithPath: $0, isDirectory: true) }
        if env["DESKPOUCH_DEMO"] == "states" {
            runStatesDemo(out: out)
            return
        }
        if env["DESKPOUCH_DEMO"] == "options" {
            runOptionsDemo(out: out)
            return
        }
        if env["DESKPOUCH_DEMO"] == "picker" {
            runPickerDemo(out: out)
            return
        }
        if env["DESKPOUCH_DEMO"] == "record" {
            // Real recording of a fixed region for 4 s, delivered through the real pipeline (saves to Movies, logs history).
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                let full = ProcessInfo.processInfo.environment["DESKPOUCH_DEMO_FULL"] != nil
                self?.screen.debugRecord(region: full ? nil : CGRect(x: 160, y: 140, width: 1040, height: 760), seconds: 4)
            }
            return
        }
        if env["DESKPOUCH_DEMO"] == "transcribe", let wav = env["DESKPOUCH_DEMO_WAV"] {
            runTranscribeDemo(wav: URL(fileURLWithPath: wav), out: out)
            return
        }
        guard env["DESKPOUCH_DEMO"] == "pill" else { return }
        if state.recent.isEmpty { seedDemoRecent() }
        var source = SimulatedLevelSource()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self else { return }
            state.isListening = true
            statusItem.beginListening()
            overlay.showListening { source.next() }
            if let button = statusItem.button { panel.open(relativeTo: button) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self, let out else { return }
            Self.writePNG(overlay.debugSnapshot(), to: out.appending(path: "app-pill.png"))
            Task { [weak self] in
                guard let self else { return }
                Self.writePNG(await panel.debugSnapshot(), to: out.appending(path: "app-panel.png"))
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
            guard let self else { return }
            state.isListening = false
            statusItem.showIdle()
            overlay.hide()
            panel.close()
        }
    }

    /// Fake Recent rows for the panel snapshot when the real history is empty. State only, nothing is written.
    private func seedDemoRecent() {
        let now = Date()
        state.recent = [
            HistoryItem(id: UUID(), toolID: "voice", createdAt: now.addingTimeInterval(-120),
                        text: "Can we move standup to 10 so the Berlin folks can join", fileURL: nil,
                        duration: 4.2, pastedInto: "Slack"),
            HistoryItem(id: UUID(), toolID: "screen", createdAt: now.addingTimeInterval(-9 * 60),
                        text: nil, fileURL: URL(fileURLWithPath: "/tmp/Recording 10.32.mp4"),
                        duration: 42, pastedInto: nil),
            HistoryItem(id: UUID(), toolID: "voice", createdAt: now.addingTimeInterval(-3600),
                        text: "Ship the plan first, then the mocks, then we talk about the rest", fileURL: nil,
                        duration: 6.1, pastedInto: "Claude"),
            HistoryItem(id: UUID(), toolID: "voice", createdAt: now.addingTimeInterval(-5 * 3600),
                        text: "Remind me to send the invoice on Friday", fileURL: nil,
                        duration: 2.8, pastedInto: nil),
            HistoryItem(id: UUID(), toolID: "voice", createdAt: now.addingTimeInterval(-30 * 3600),
                        text: "Draft: thanks for the intro, happy to chat next week", fileURL: nil,
                        duration: 3.4, pastedInto: "Mail"),
        ]
        state.historyCount = 48
    }

    /// `DESKPOUCH_DEMO=states` walks every pill state, 1.6 s each, dumping a PNG per state.
    /// The recording state also logs whether the pill takes clicks and clear pixels pass them through.
    private func runStatesDemo(out: URL?) {
        let states: [(String, PillState)] = [
            ("preparing", .preparing("Downloading model · 42%")),
            ("transcribing", .transcribing(detail: "Parakeet v3")),
            ("pasted", .pasted(target: "Slack")),
            ("copied", .copied),
            ("saved", .saved(name: "Recording 2026-09-15 10.32.05.mp4", copied: true)),
            ("recording", .recording(detail: "1040 × 760 · 60 fps")),
            ("failed", .failed("Nothing heard")),
        ]
        for (i, (name, state)) in states.enumerated() {
            let t = 1 + Double(i) * 1.6
            DispatchQueue.main.asyncAfter(deadline: .now() + t) { [weak self] in
                guard let self else { return }
                if case .recording(let detail) = state {
                    overlay.showRecording(detail: detail, since: Date().addingTimeInterval(-42)) { log.info("demo: stop tapped") }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                        guard let self else { return }
                        let centre = overlay.debugPillCenter
                        let aside = CGPoint(x: centre.x - 300, y: centre.y - 40)
                        let atPill = NSWindow.windowNumber(at: centre, belowWindowWithWindowNumber: 0)
                        let atClear = NSWindow.windowNumber(at: aside, belowWindowWithWindowNumber: 0)
                        log.info("demo: hit test pill=\(atPill) clear=\(atClear) (clear must differ from pill)")
                    }
                } else {
                    overlay.show(state)
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + t + 1.3) { [weak self] in
                guard let self, let out else { return }
                Self.writePNG(overlay.debugSnapshot(), to: out.appending(path: "state-\(name).png"))
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1 + Double(states.count) * 1.6) { [weak self] in
            self?.overlay.hide()
        }
    }

    /// `DESKPOUCH_DEMO=options` walks the panel: main list, Voice view, Screen view with a dropdown open, General.
    private func runOptionsDemo(out: URL?) {
        if state.recent.isEmpty { seedDemoRecent() }
        func snap(_ name: String, at seconds: Double) {
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
                guard let self, let out else { return }
                log.info("demo: snapshot \(name, privacy: .public) visible=\(self.panel.isVisible) presented=\(self.state.panelPresented) view=\(String(describing: self.state.panelView), privacy: .public) popup=\(self.state.popups.isOpen)")
                Task { [weak self] in
                    guard let self else { return }
                    Self.writePNG(await panel.debugSnapshot(), to: out.appending(path: "\(name).png"))
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self else { return }
            refreshPanelInfo()
            // The screenshots can raise the system's screen capture alert, which would take key status and close the panel.
            panel.holdsOpen = true
            if let button = statusItem.button { panel.open(relativeTo: button) }
        }
        snap("app-main", at: 2.0)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [weak self] in
            self?.state.panelView = .tool(VoiceToolView.toolID)
        }
        snap("app-voice-options", at: 3.0)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) { [weak self] in
            self?.state.panelView = .tool(ScreenToolView.toolID)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.6) { [weak self] in
            guard let self else { return }
            let options = RecorderSettings.Quality.allCases
            state.popups.toggle("screen.quality", items: options.enumerated().map { index, quality in
                PopupItem(id: index, title: quality.label, selected: quality == state.recorderSettings.quality)
            }) { _ in }
        }
        snap("app-screen-options", at: 4.6)
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.2) { [weak self] in
            guard let self else { return }
            state.popups.close()
            state.panelView = .general
        }
        snap("app-general", at: 6.4)
        DispatchQueue.main.asyncAfter(deadline: .now() + 7) { [weak self] in
            guard let self else { return }
            state.historyQuery = ""
            state.historyFilter = .all
            loadHistory(more: false)
            state.panelView = .history
        }
        snap("app-history", at: 8.2)
        DispatchQueue.main.asyncAfter(deadline: .now() + 9.5) { [weak self] in
            self?.panel.holdsOpen = false
            self?.panel.close()
        }
    }

    /// `DESKPOUCH_DEMO=picker` opens the region picker with a region drawn, dumps it, and cancels.
    private func runPickerDemo(out: URL?) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.screen.debugOpenPicker(region: CGRect(x: 160, y: 140, width: 1040, height: 760))
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self, let out else { return }
            Self.writePNG(screen.debugSnapshotPicker(), to: out.appending(path: "app-picker.png"))
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.screen.debugCancelPicker()
        }
    }

    /// `DESKPOUCH_DEMO=transcribe` with `DESKPOUCH_DEMO_WAV=<16 kHz mono float wav>` runs the engine on a file.
    /// Shows the pill states, logs the transcript, never pastes.
    private func runTranscribeDemo(wav: URL, out: URL?) {
        Task { [weak self] in
            guard let self else { return }
            guard let samples = WavLoader.samples16kMono(wav) else {
                NSLog("deskpouch demo: could not read %@ as 16 kHz mono float", wav.path)
                return
            }
            try? await Task.sleep(for: .seconds(1))
            let text = await voice.debugTranscribe(samples)
            NSLog("deskpouch demo: transcript = %@", text ?? "<nil>")
            if let out { Self.writePNG(overlay.debugSnapshot(), to: out.appending(path: "demo-transcript.png")) }
            if let out, let text { try? text.write(to: out.appending(path: "demo-transcript.txt"), atomically: true, encoding: .utf8) }
            try? await Task.sleep(for: .seconds(1))
            overlay.hide()
        }
    }

    private static func writePNG(_ image: NSImage?, to url: URL) {
        guard let image, let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            log.error("demo: could not encode \(url.lastPathComponent, privacy: .public)")
            return
        }
        do { try png.write(to: url) } catch { log.error("demo: write failed \(String(describing: error), privacy: .public)") }
    }
}
