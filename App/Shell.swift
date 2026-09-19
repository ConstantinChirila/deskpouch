import AVFoundation
import AppKit
import DeskpouchCore
import DeskpouchGallery
import ImageIO
import ToolColor
import ToolScreenRecorder
import ToolScreenshot
import ToolVoice
import os

private let log = Logger(subsystem: "com.constantinchirila.deskpouch", category: "shell")

/// Composition root. Owns hotkeys, overlay, output pipeline, status item, the menubar panel and the tools.
@MainActor
final class Shell {
    let state = ShellState()
    private let hotkeys = HotkeyCenter()
    private let overlay = OverlayController()
    private let editor = EditorWindowController()
    private let presence = WindowPresence()
    /// Nil when the history database could not be opened.
    private var gallery: GalleryWindowController?
    private let history: HistoryStore?
    private let effects = SystemOutputEffects()
    private let pipeline: OutputPipeline
    private let statusItem = StatusItemController()
    private lazy var panel = MenuPanelController(state: state, actions: panelActions)

    private let voice = VoiceTool()
    private let screen = ScreenRecorderTool()
    private let screenshot = ScreenshotTool()
    private let color = ColorTool()
    private var tools: [Tool] { [voice, screen, screenshot, color] }

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
        pipeline = OutputPipeline(effects: effects, history: history)
    }

    func start() {
        editor.deliver = { [weak self] result in self?.deliver(result) }
        editor.onOpenChange = { [weak self] open in self?.presence.changed(open) }
        if let history {
            let gallery = GalleryWindowController(store: history, actions: GalleryActions(
                copy: { [weak self] item in self?.copyRecent(item) },
                reveal: { item in
                    guard let file = item.fileURL else { return }
                    NSWorkspace.shared.activateFileViewerSelecting([file])
                },
                edit: { [weak self] item in self?.panelActions.edit(item) },
                editLabel: { $0.editLabel }
            ))
            gallery.onOpenChange = { [weak self] open in self?.presence.changed(open) }
            self.gallery = gallery
        }
        let context = ToolContext(
            overlay: overlay,
            editor: editor,
            emit: { [weak self] result in self?.deliver(result) },
            activity: { [weak self] _, activity in self?.activityChanged(activity) }
        )
        for tool in tools {
            state.output.registerDefault(tool.defaultOutput, for: tool.id)
            tool.attach(context)
            registerPress(tool)
            registerHold(tool)
            if state.switches.isEnabled(tool.id) { tool.activate() }
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
        state.shotKey = screenshot.pressKey ?? .commandShift2
        state.shotSettings = screenshot.settings
        state.shotFolder = state.output.config(for: screenshot.id).folder
        state.colorKey = color.pressKey ?? .commandShift9
        state.colorSettings = color.settings
        state.mainScreenScale = NSScreen.main?.backingScaleFactor ?? 2
        refreshVoiceEngine()
        state.voiceMicrophoneUID = voice.microphoneUID
        state.voiceSkipFillers = voice.skipFillers
        screen.onStatus = { [weak self] text in
            guard let self else { return }
            state.screenStatus = text
            state.recorderSettings = screen.settings
        }
        screenshot.onStatus = { [weak self] _ in
            guard let self else { return }
            state.shotSettings = screenshot.settings
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
        #if DEBUG
        runDemoIfRequested()
        #endif
    }

    func stop() {
        hotkeys.stop()
        permissionPoll?.invalidate()
        recordingTimer?.invalidate()
    }

    // MARK: Hotkeys

    /// Registers the tool's hold key, replacing an earlier one. A switched-off tool only loses its registration.
    private func registerHold(_ tool: Tool) {
        if let old = holdRegistrations.removeValue(forKey: tool.id) { hotkeys.unregister(old) }
        guard state.switches.isEnabled(tool.id), let key = tool.holdKey else { return }
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
            case .cancelled:
                // The modifier was part of a typed chord; stop quietly, no cue.
                state.isListening = false
                statusItem.showIdle()
                tool.holdCancelled()
            }
        }
    }

    /// Registers the tool's key combo, replacing an earlier one. A switched-off tool only loses its registration.
    private func registerPress(_ tool: Tool) {
        if let old = pressRegistrations.removeValue(forKey: tool.id) { hotkeys.unregister(old) }
        setKeyTaken(tool.id, false)
        guard state.switches.isEnabled(tool.id), let combo = tool.pressKey else { return }
        if let registration = hotkeys.registerPress(combo, handler: { [weak tool] in tool?.keyPressed() }) {
            pressRegistrations[tool.id] = registration
            setKeyTaken(tool.id, false)
        } else {
            log.error("\(combo.display, privacy: .public) is taken by another app")
            setKeyTaken(tool.id, true)
        }
    }

    /// Mirrors the "taken" flag into the row for whichever press-key tool this is; a hold-key tool (voice) has
    /// no such flag.
    private func setKeyTaken(_ toolID: String, _ taken: Bool) {
        if toolID == screen.id { state.screenKeyTaken = taken }
        if toolID == screenshot.id { state.shotKeyTaken = taken }
        if toolID == color.id { state.colorKeyTaken = taken }
    }

    /// General's per-tool switch. Off frees the hotkeys first, so nothing new starts while the tool winds down.
    private func setToolEnabled(_ toolID: String, _ enabled: Bool) {
        guard let tool = tools.first(where: { $0.id == toolID }),
              state.switches.isEnabled(toolID) != enabled else { return }
        state.switches.set(toolID, enabled: enabled)
        registerHold(tool)
        registerPress(tool)
        if enabled {
            tool.activate()
        } else {
            if tool.holdKey != nil, state.isListening {
                state.isListening = false
                statusItem.showIdle()
            }
            tool.deactivate()
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

    private func setShotPressKey(_ combo: KeyCombo) {
        screenshot.pressKey = combo
        state.shotKey = combo
        registerPress(screenshot)
    }

    private func setColorPressKey(_ combo: KeyCombo) {
        color.pressKey = combo
        state.colorKey = combo
        registerPress(color)
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
        refreshVoiceEngine()
        state.microphones = AudioInputDevices.all()
        refreshRecent()
    }

    /// Engine name, options, language list and download state for the Voice view.
    private func refreshVoiceEngine() {
        state.voiceEngineID = voice.engine.rawValue
        state.voiceEngine = voice.engineName
        state.voiceEngines = VoiceEngine.allCases.map {
            ShellState.EngineOption(id: $0.rawValue, name: $0.name, detail: voice.engineDetail($0))
        }
        state.voiceModelStatus = voice.modelStatus
        state.parakeetDownloaded = voice.parakeetDownloaded
        state.voiceLanguages = voice.supportedLanguages
        state.voiceLanguage = voice.language
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

    private func chooseScreenshotFolder() {
        let open = NSOpenPanel()
        open.canChooseDirectories = true
        open.canChooseFiles = false
        open.canCreateDirectories = true
        open.directoryURL = state.shotFolder ?? ScreenshotTool.defaultFolder
        open.prompt = "Use folder"
        open.message = "Screenshots are saved here"
        panel.holdsOpen = true
        NSApp.activate()
        open.begin { [weak self] response in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.panel.holdsOpen = false
                guard response == .OK, let url = open.url else { return }
                self.state.output.update(self.screenshot.id) { $0.folder = url }
                self.state.shotFolder = url
            }
        }
    }

    /// Loads the first page for the current query and filter, appends the next one, or re-reads what is shown.
    private func loadHistory(_ load: HistoryPage.Load) {
        guard let history else { return }
        do {
            let page = try history.page(
                load,
                after: HistoryPage(items: state.historyItems, matches: state.historyMatches),
                query: state.historyQuery.trimmingCharacters(in: .whitespaces),
                toolID: state.historyFilter.toolID,
                pageSize: HistoryView.pageSize
            )
            state.historyItems = page.items
            state.historyMatches = page.matches
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

    /// The first frame of a video, small. Nil when it cannot be read.
    private static func poster(of file: URL) async -> CGImage? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: file))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 320, height: 320)
        return try? await generator.image(at: .zero).image
    }

    private func deliver(_ result: ToolResult) {
        Task { [weak self] in
            guard let self else { return }
            var config = state.output.config(for: result.toolID)
            if !state.general.keepHistory { config.actions.remove(.history) }
            let delivery = await pipeline.deliver(result, config: config)
            if delivery.recorded {
                refreshRecent()
                if state.panelView == .history { loadHistory(.refresh) }
            }
            // A new hold started while this result was on its way: leave its listening pill alone.
            if state.isListening { return }
            if let followUp = result.followUp, let file = delivery.savedTo ?? result.fileURL {
                let title = switch (delivery.savedTo != nil, delivery.copied) {
                case (true, true): "Saved and copied"
                case (true, false): "Saved"
                case (false, true): "Copied"
                case (false, false): "Captured"
                }
                // A recording brings no image of its own: its first frame fills the pill's tile.
                var thumbnail = result.image
                if thumbnail == nil, result.kind == .recording {
                    thumbnail = await Self.poster(of: file)
                    if state.isListening { return }
                }
                overlay.showCaptured(
                    thumbnail: thumbnail, title: title, hint: file.lastPathComponent, action: followUp.label
                ) {
                    followUp.perform(file)
                }
            } else if let target = delivery.pastedInto {
                overlay.flash(.pasted(target: target))
            } else if let saved = delivery.savedTo {
                overlay.flash(.saved(name: saved.lastPathComponent, copied: delivery.copied), for: .seconds(2))
            } else if delivery.copied {
                overlay.flash(.copied)
            } else {
                overlay.hide()
            }
        }
    }

    private func refreshRecent() {
        guard let history else { return }
        do {
            state.recent = try history.recent(limit: Self.recentLimit)
            gallery?.historyChanged()
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
        } else if item.kind == .screenshot, let file = item.fileURL, let image = Self.loadImage(file) {
            // Matches the first copy: PNG + lazy TIFF on the pasteboard, not a file reference. The file's own
            // bytes are already PNG, so they go straight on the pasteboard instead of round-tripping the image
            // through another encode; `image` is still needed to build the lazy TIFF representation.
            effects.copyImage(image, pngData: try? Data(contentsOf: file))
        } else if let file = item.fileURL {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([file as NSURL])
        } else {
            return
        }
        overlay.flash(.copied)
    }

    private static func loadImage(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
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
            copyText: { [weak self] text in
                guard let self else { return }
                Paster.copy(text)
                overlay.flash(.copied)
            },
            revealRecent: { item in
                guard let file = item.fileURL else { return }
                NSWorkspace.shared.activateFileViewerSelecting([file])
            },
            openGallery: { [weak self] item in
                guard let self else { return }
                panel.close()
                gallery?.present(selecting: item?.id)
            },
            edit: { [weak self] item in
                guard let self, let file = item.fileURL else { return }
                panel.close()
                if item.kind == .recording {
                    screen.trim(fileURL: file)
                } else {
                    screenshot.annotate(fileURL: file)
                }
            },
            setHoldKey: { [weak self] key in self?.setHoldKey(key) },
            setPressKey: { [weak self] combo in self?.setPressKey(combo) },
            setToolEnabled: { [weak self] id, on in self?.setToolEnabled(id, on) },
            setVoiceLanguage: { [weak self] code in
                guard let self else { return }
                voice.language = code
                state.voiceLanguage = voice.language
            },
            setVoiceEngine: { [weak self] id in
                guard let self, let engine = VoiceEngine(rawValue: id) else { return }
                voice.engine = engine
                refreshVoiceEngine()
            },
            removeVoiceModel: { [weak self] in
                guard let self else { return }
                do {
                    try voice.removeParakeetDownload()
                } catch {
                    log.error("remove model failed: \(String(describing: error), privacy: .public)")
                }
                refreshVoiceEngine()
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
            setShotPressKey: { [weak self] combo in self?.setShotPressKey(combo) },
            updateScreenshot: { [weak self] change in
                guard let self else { return }
                var settings = screenshot.settings
                change(&settings)
                screenshot.settings = settings
                state.shotSettings = settings
            },
            chooseScreenshotFolder: { [weak self] in self?.chooseScreenshotFolder() },
            setColorPressKey: { [weak self] combo in self?.setColorPressKey(combo) },
            updateColor: { [weak self] change in
                guard let self else { return }
                var settings = color.settings
                change(&settings)
                color.settings = settings
                state.colorSettings = settings
            },
            setLaunchAtLogin: { [weak self] on in self?.state.general.setLaunchAtLogin(on) },
            setPillPosition: { [weak self] position in
                guard let self else { return }
                state.general.pillPosition = position
                overlay.position = position
            },
            clearHistory: { [weak self] in self?.clearHistory() },
            loadHistory: { [weak self] more in self?.loadHistory(more ? .more : .first) },
            deleteHistory: { [weak self] item in self?.deleteHistory(item) },
            openPermissionSettings: { [weak self] in self?.openPermissionSettings() },
            closePanel: { [weak self] in self?.panel.close() },
            quit: { NSApp.terminate(nil) }
        )
    }

    // MARK: Demo

    // Debug builds only: the demo modes record the screen and write files on an environment variable.
    #if DEBUG

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
        if env["DESKPOUCH_DEMO"] == "gallery" {
            runGalleryDemo(out: out)
            return
        }
        if env["DESKPOUCH_DEMO"] == "trim" {
            runTrimDemo(out: out)
            return
        }
        if env["DESKPOUCH_DEMO"] == "shot-picker" {
            // The real interactive flow, not the `shot` demo's shortcut: `keyPressed()` opens the picker exactly
            // as ⌘⇧2 does, a region is drawn through the same `PickerModel` calls a drag uses, and `confirm()` is
            // the same call the Return key monitor and the toolbar's Capture button make. Exercises
            // pickerFinished -> dismiss -> capture for real, so it catches bugs `shot` (no picker) cannot.
            runShotPickerDemo(out: out)
            return
        }
        if env["DESKPOUCH_DEMO"] == "annotate-pill" {
            // Capture, then press the pill's Annotate at 5 s. Activate another app before that to check the
            // editor still comes to the front.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.screenshot.debugCapture(region: CGRect(x: 160, y: 140, width: 1040, height: 760))
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                log.info("demo(annotate-pill): tapping, frontmost=\(NSWorkspace.shared.frontmostApplication?.localizedName ?? "nil", privacy: .public)")
                self?.overlay.debugTapFollowUp()
            }
            return
        }
        if env["DESKPOUCH_DEMO"] == "annotate-two" {
            // Opens the two newest screenshot rows side by side, then the newest again: expects 2 windows.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                guard let self else { return }
                let rows = state.recent.filter(\.canAnnotate).prefix(2)
                guard rows.count == 2 else {
                    log.error("demo(annotate-two): needs two screenshot rows in Recent")
                    return
                }
                rows.forEach { self.panelActions.edit($0) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                    guard let self, let first = rows.first else { return }
                    let before = editor.documents.count
                    panelActions.edit(first)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                        guard let self else { return }
                        log.info("demo(annotate-two): open after two = \(before), after reopening the first = \(self.editor.documents.count) (want 2 and 2)")
                    }
                }
            }
            return
        }
        if env["DESKPOUCH_DEMO"] == "annotate" {
            runAnnotateDemo(out: out)
            return
        }
        if env["DESKPOUCH_DEMO"] == "color" {
            runColorDemo(point: env["DESKPOUCH_DEMO_POINT"], out: out)
            return
        }
        if env["DESKPOUCH_DEMO"] == "shot" {
            // Real screenshot, no picker, delivered through the real pipeline (saves to Pictures, logs history
            // with a thumbnail). Annotate does not exist yet, so this stops at capture. `DESKPOUCH_DEMO_SHOT=window`
            // captures the frontmost normal window of another app instead of the default fixed region, to check
            // window-mode sizing and the shadow option (open a target window first, e.g. `open ~` for Finder).
            let window = env["DESKPOUCH_DEMO_SHOT"] == "window"
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                if window {
                    self?.screenshot.debugCaptureWindow()
                } else {
                    self?.screenshot.debugCapture(region: CGRect(x: 160, y: 140, width: 1040, height: 760))
                }
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
            ("captured", .captured(title: "Saved and copied", hint: "Screenshot 2026-09-16 14.05.02.png", action: "Annotate")),
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
        snap("app-main", at: 1.8)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self else { return }
            // Newest colour row unfolded, so the formats list is in the snapshot.
            state.expandedColor = state.recent.first { $0.kind == .color }?.id
        }
        snap("app-main-color", at: 2.6)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) { [weak self] in
            guard let self else { return }
            state.expandedColor = nil
            state.panelView = .tool(VoiceToolView.toolID)
        }
        snap("app-voice-options", at: 3.4)
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
            state.panelView = .tool(ScreenshotToolView.toolID)
        }
        snap("app-shot-options", at: 6.4)
        DispatchQueue.main.asyncAfter(deadline: .now() + 7) { [weak self] in
            guard let self else { return }
            state.panelView = .tool(ColorToolView.toolID)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 7.4) { [weak self] in
            guard let self else { return }
            state.popups.toggle("color.format", items: ColorFormat.allCases.enumerated().map { index, format in
                PopupItem(id: index, title: format.label, detail: format.string(for: SRGBColor(hex: 0xF59E0B)), selected: format == state.colorSettings.format)
            }) { _ in }
        }
        snap("app-color-options", at: 8.4)
        DispatchQueue.main.asyncAfter(deadline: .now() + 9) { [weak self] in
            guard let self else { return }
            state.popups.close()
            state.panelView = .general
        }
        snap("app-general", at: 10.2)
        DispatchQueue.main.asyncAfter(deadline: .now() + 10.8) { [weak self] in
            guard let self else { return }
            state.historyQuery = ""
            state.historyFilter = .all
            loadHistory(.first)
            state.panelView = .history
        }
        snap("app-history", at: 12)
        DispatchQueue.main.asyncAfter(deadline: .now() + 13.3) { [weak self] in
            self?.panel.holdsOpen = false
            self?.panel.close()
        }
    }

    /// `DESKPOUCH_DEMO=shot-picker` drives the real ⌘⇧2 flow end to end: `keyPressed()` opens the picker,
    /// `PickerModel.dragChanged`/`dragEnded` draw a region the same way a real drag does, and `confirm()` is the
    /// same call the Return key monitor and the toolbar's Capture button make. Verification only: logs whether
    /// the picker's overlay windows are gone after capture, whether the pasteboard has an image, and the most
    /// recent history row, all at `os.Logger` info/error level (`log stream --predicate 'subsystem ==
    /// "com.constantinchirila.deskpouch"'`). With `DESKPOUCH_DEMO_OUT=<dir>` also dumps a mid-selection picker
    /// snapshot so the selection's interior can be checked for a clear (non-dimmed) cutout.
    private func runShotPickerDemo(out: URL?) {
        // Each step schedules the next one relative to when IT runs, not to the demo's start: a slow first
        // render (Metal/shader warm-up on the picker's blurred, shadowed overlay, seen to cost several seconds
        // on a cold launch) must not eat into the gap the later steps rely on, or their checks fire before the
        // async capture pipeline they are supposed to be timing has had a chance to finish.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self else { return }
            log.info("demo(shot-picker): keyPressed() -> opening the real picker")
            screenshot.keyPressed()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.shotPickerDemoDrawRegion(out: out) }
        }
    }

    private func shotPickerDemoDrawRegion(out: URL?) {
        guard let model = screenshot.debugPickerModel, let screen = model.screen(model.toolbarScreenID) else {
            log.error("demo(shot-picker): picker never opened (debugPickerModel is nil) -- bug 2/3 territory")
            return
        }
        let rect = CGRect(x: 160, y: 140, width: 1040, height: 760)
        model.dragChanged(screenID: screen.id, location: rect.origin)
        model.dragChanged(screenID: screen.id, location: CGPoint(x: rect.maxX, y: rect.maxY))
        model.dragEnded(screenID: screen.id, location: CGPoint(x: rect.maxX, y: rect.maxY))
        log.info("demo(shot-picker): region drawn (\(Int(rect.width)) x \(Int(rect.height)))")
        if let out {
            let snapshotStart = Date()
            Self.writePNG(screenshot.debugSnapshotPicker(), to: out.appending(path: "app-shot-picker.png"))
            log.info("demo(shot-picker): mid-selection snapshot written in \(Date().timeIntervalSince(snapshotStart))s")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.shotPickerDemoConfirm() }
    }

    private func shotPickerDemoConfirm() {
        let before = Self.deskpouchOverlayWindowCount()
        log.info("demo(shot-picker): overlay windows before confirm = \(before)")
        guard let model = screenshot.debugPickerModel else {
            log.error("demo(shot-picker): model gone before confirm")
            return
        }
        // Same call the Return key monitor and the toolbar's Capture button make: this exercises
        // PickerModel.confirm -> onFinish -> ScreenshotTool.pickerFinished -> dismiss -> capture for real.
        model.confirm()
        // `dismiss()` orders every picker window out synchronously as part of this very call (confirm ->
        // onFinish -> pickerFinished -> dismiss, no `await` in between), so this should already read 0.
        let immediatelyAfter = Self.deskpouchOverlayWindowCount()
        log.info("demo(shot-picker): overlay windows immediately after confirm() returns = \(immediatelyAfter) (dismiss() is synchronous, so this should already be 0)")
        // The capture itself is async (ShareableContentLoader.load, SCScreenshotManager.captureImage, a
        // detached PNG write, then the output pipeline): give it real time before checking the pasteboard and
        // history, instead of the fixed-offset schedule that made the first version of this demo check within
        // 9 ms of calling confirm(), long before the capture could possibly have finished.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.shotPickerDemoVerify() }
    }

    private func shotPickerDemoVerify() {
        let after = Self.deskpouchOverlayWindowCount()
        log.info("demo(shot-picker): overlay windows 3s after confirm = \(after) (must be 0 for bug 2 to be fixed)")
        let types = (NSPasteboard.general.types ?? []).map(\.rawValue).joined(separator: ", ")
        let hasImage = NSPasteboard.general.types?.contains(.png) == true
        log.info("demo(shot-picker): pasteboard types = [\(types, privacy: .public)], has PNG = \(hasImage) (must be true for bug 3 to be fixed)")
        let recent = state.recent.first
        let ageSeconds = recent.map { Date().timeIntervalSince($0.createdAt) } ?? -1
        log.info("demo(shot-picker): most recent history row: tool=\(recent?.toolID ?? "nil", privacy: .public) age=\(ageSeconds)s file=\(recent?.fileURL?.path ?? "nil", privacy: .public) (age should be a few seconds, not stale, for bug 2/3 to be fixed)")
    }

    /// Deskpouch's own overlay-level windows (the picker's borderless panels are `.screenSaver` level, one per
    /// screen): should be zero once a picker has been dismissed. Verification only.
    private static func deskpouchOverlayWindowCount() -> Int {
        guard let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else { return -1 }
        return list.filter { info in
            (info[kCGWindowOwnerName as String] as? String) == "Deskpouch"
                && (info[kCGWindowLayer as String] as? Int ?? 0) >= Int(NSWindow.Level.screenSaver.rawValue)
        }.count
    }

    /// `DESKPOUCH_DEMO=annotate`: a real capture through the pipeline, the captured pill, then the editor opened
    /// from the newest screenshot row (the hover button's path) with sample marks, exported through the pipeline.
    /// Logs whether the annotated file sits beside the original and the pasteboard holds a PNG. With
    /// `DESKPOUCH_DEMO_OUT=<dir>` writes the pill and the editor window.
    private func runAnnotateDemo(out: URL?) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.screenshot.debugCapture(region: CGRect(x: 160, y: 140, width: 1040, height: 760))
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { [weak self] in
            guard let self else { return }
            log.info("demo(annotate): pill = \(String(describing: self.overlay.state), privacy: .public)")
            if let out { Self.writePNG(overlay.debugSnapshot(), to: out.appending(path: "app-pill-captured.png")) }
            guard let item = state.recent.first(where: { $0.kind == .screenshot }), item.canAnnotate else {
                log.error("demo(annotate): no screenshot row to annotate")
                return
            }
            log.info("demo(annotate): annotating \(item.fileURL?.path ?? "nil", privacy: .public)")
            overlay.hide()
            panelActions.edit(item)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.annotateDemoMark(out: out, original: item.fileURL) }
        }
    }

    private func annotateDemoMark(out: URL?, original: URL?) {
        guard screenshot.debugAnnotateOpenDocument() else {
            log.error("demo(annotate): editor did not open")
            return
        }
        log.info("demo(annotate): editor open = \(self.editor.isOpen)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self else { return }
            Task { [weak self] in
                guard let self else { return }
                if let out, let number = editor.debugWindowNumber {
                    Self.writePNG(await WindowSnapshot.capture(windowNumber: number), to: out.appending(path: "app-editor.png"))
                }
                editor.debugRequestClose()
                try? await Task.sleep(for: .milliseconds(400))
                log.info("demo(annotate): close with marks -> prompt=\(self.editor.debugConfirmingDiscard) open=\(self.editor.isOpen)")
                if let out, let number = editor.debugWindowNumber {
                    Self.writePNG(await WindowSnapshot.capture(windowNumber: number), to: out.appending(path: "app-editor-discard.png"))
                }
                editor.debugKeepEditing()
                editor.debugExport()
                try? await Task.sleep(for: .seconds(2.5))
                let annotated = state.recent.first
                let besideOriginal = annotated?.fileURL?.deletingLastPathComponent().path == original?.deletingLastPathComponent().path
                let exists = annotated?.fileURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
                let hasPNG = NSPasteboard.general.types?.contains(.png) == true
                let originalKept = original.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
                log.info("demo(annotate): newest row = \(annotated?.fileURL?.lastPathComponent ?? "nil", privacy: .public) exists=\(exists) besideOriginal=\(besideOriginal) originalKept=\(originalKept) pasteboardPNG=\(hasPNG) editorOpen=\(self.editor.isOpen) pill=\(String(describing: self.overlay.state), privacy: .public)")
                if let out { Self.writePNG(overlay.debugSnapshot(), to: out.appending(path: "app-pill-after-export.png")) }
            }
        }
    }

    /// `DESKPOUCH_DEMO=gallery`: opens the gallery on the real history and steps down it, one PNG per row for the
    /// first rows (app-gallery-N.png) with `DESKPOUCH_DEMO_OUT`. Deletes nothing.
    private func runGalleryDemo(out: URL?) {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self, let gallery else {
                log.error("demo(gallery): no history store")
                return
            }
            gallery.present()
            for step in 0..<4 {
                try? await Task.sleep(for: .seconds(1.5))
                let focused = gallery.model.focused
                log.info("demo(gallery): \(step) focused=\(focused?.kind.rawValue ?? "nil", privacy: .public) total=\(gallery.model.total) loaded=\(gallery.model.items.count)")
                if let out, let number = gallery.debugWindowNumber {
                    Self.writePNG(await WindowSnapshot.capture(windowNumber: number), to: out.appending(path: "app-gallery-\(step).png"))
                }
                gallery.model.move(by: 1, extending: false)
            }
            // Recordings: the newest mp4, Space to play, and the player's clock a moment later.
            gallery.model.query.kinds = [.recording]
            if let recording = gallery.model.items.first(where: { $0.fileURL?.pathExtension.lowercased() != "gif" }) {
                gallery.model.click(recording.id, command: false, shift: false)
                try? await Task.sleep(for: .seconds(1.5))
                if let out, let number = gallery.debugWindowNumber {
                    Self.writePNG(await WindowSnapshot.capture(windowNumber: number), to: out.appending(path: "app-gallery-video.png"))
                }
                gallery.debugPressSpace()
                try? await Task.sleep(for: .seconds(1.5))
                log.info("demo(gallery): video \(gallery.debugVideoState, privacy: .public)")
                if let out, let number = gallery.debugWindowNumber {
                    Self.writePNG(await WindowSnapshot.capture(windowNumber: number), to: out.appending(path: "app-gallery-video-playing.png"))
                }
                gallery.debugPressSpace()
            }
            if let gif = gallery.model.items.first(where: { $0.fileURL?.pathExtension.lowercased() == "gif" }) {
                gallery.model.click(gif.id, command: false, shift: false)
                try? await Task.sleep(for: .seconds(1.5))
                log.info("demo(gallery): gif after 1.5 s: \(gallery.debugVideoState, privacy: .public)")
                gallery.debugPressSpace()
                log.info("demo(gallery): gif after Space: \(gallery.debugVideoState, privacy: .public)")
                if let out, let number = gallery.debugWindowNumber {
                    Self.writePNG(await WindowSnapshot.capture(windowNumber: number), to: out.appending(path: "app-gallery-gif.png"))
                }
            }
            gallery.model.query.kinds = nil
            gallery.debugFocusSearch()
            try? await Task.sleep(for: .seconds(1.5))
            if let out, let number = gallery.debugWindowNumber {
                Self.writePNG(await WindowSnapshot.capture(windowNumber: number), to: out.appending(path: "app-gallery-search.png"))
            }
        }
    }

    /// `DESKPOUCH_DEMO=trim`: a real 4 s recording through the pipeline, the pill's Trim pressed, 1 s cut off each
    /// side, exported as mp4; then the same from the recording's row as a GIF. Logs each export's name, length and
    /// size. With `DESKPOUCH_DEMO_OUT` writes app-pill-trim.png and app-trim.png.
    private func runTrimDemo(out: URL?) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.screen.debugRecord(region: CGRect(x: 160, y: 140, width: 1040, height: 760), seconds: 4)
        }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(7.5))
            guard let self else { return }
            log.info("demo(trim): pill = \(String(describing: self.overlay.state), privacy: .public)")
            if let out { Self.writePNG(overlay.debugSnapshot(), to: out.appending(path: "app-pill-trim.png")) }
            guard let original = state.recent.first(where: { $0.canTrim }) else {
                log.error("demo(trim): no recording row to trim")
                return
            }
            overlay.debugTapFollowUp()
            for gif in [false, true] {
                if gif { panelActions.edit(original) }
                try? await Task.sleep(for: .seconds(2))
                guard let kept = screen.debugTrimOpenDocument(cutting: 1, gif: gif) else {
                    log.error("demo(trim): editor did not open")
                    return
                }
                try? await Task.sleep(for: .seconds(1.5))
                if let out, !gif, let number = editor.debugWindowNumber {
                    Self.writePNG(await WindowSnapshot.capture(windowNumber: number), to: out.appending(path: "app-trim.png"))
                }
                editor.debugExport()
                try? await Task.sleep(for: .seconds(gif ? 6 : 3))
                let row = state.recent.first
                let size = (row?.fileURL).flatMap { try? FileManager.default.attributesOfItem(atPath: $0.path)[.size] as? NSNumber }
                let beside = row?.fileURL?.deletingLastPathComponent().path == original.fileURL?.deletingLastPathComponent().path
                let originalKept = original.fileURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
                log.info("demo(trim): kept=\(kept) newest row = \(row?.fileURL?.lastPathComponent ?? "nil", privacy: .public) duration=\(row?.duration ?? -1) bytes=\(size?.intValue ?? -1) besideOriginal=\(beside) originalKept=\(originalKept) editorOpen=\(self.editor.isOpen)")
            }
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
                log.error("demo: could not read \(wav.path, privacy: .public) as 16 kHz mono float")
                return
            }
            try? await Task.sleep(for: .seconds(1))
            let text = await voice.debugTranscribe(samples)
            log.info("demo: transcript = \(text ?? "<nil>", privacy: .private)")
            if let out { Self.writePNG(overlay.debugSnapshot(), to: out.appending(path: "demo-transcript.png")) }
            if let out, let text { try? text.write(to: out.appending(path: "demo-transcript.txt"), atomically: true, encoding: .utf8) }
            try? await Task.sleep(for: .seconds(1))
            overlay.hide()
        }
    }

    /// `DESKPOUCH_DEMO=color` opens the loupe as ⌘⇧9 would, parks it on a point (AppKit global, `x,y` in
    /// `DESKPOUCH_DEMO_POINT`, the main screen's centre otherwise), logs what it sampled and picks it through the
    /// real pipeline. With `DESKPOUCH_DEMO_OUT` it also writes the loupe's screen as `app-loupe.png`.
    private func runColorDemo(point: String?, out: URL?) {
        let parts = (point ?? "").split(separator: ",").compactMap { Double($0) }
        let target = parts.count == 2
            ? CGPoint(x: parts[0], y: parts[1])
            : CGPoint(x: (NSScreen.main?.frame.midX ?? 400), y: (NSScreen.main?.frame.midY ?? 400))
        let realInput = ProcessInfo.processInfo.environment["DESKPOUCH_DEMO_CLICK"] != nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self else { return }
            log.info("demo(color): opening the loupe at \(target.x, privacy: .public),\(target.y, privacy: .public)")
            if realInput {
                // The real path: park the cursor, then press ⌘⇧9 as a user would, so the Carbon hotkey opens the
                // loupe and the app activates off a genuine key press.
                postMouse(.mouseMoved, at: target)
                postKey(25, flags: [.maskCommand, .maskShift])
            } else {
                color.debugOpen(at: target)
            }
            log.info("demo(color): loupe windows = \(self.color.debugWindowCount) (one per screen)")
            // The display capture takes a moment; the loupe shows "Reading screen" until it lands.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
                guard let self else { return }
                log.info("demo(color): sampled \(self.color.debugValue ?? "nothing", privacy: .public) at pixel \(self.color.debugPixel, privacy: .public)")
                if let out { Self.writePNG(color.debugSnapshot(), to: out.appending(path: "app-loupe.png")) }
                guard realInput else {
                    color.debugPick()
                    colorDemoReport()
                    return
                }
                // Real input, posted the way a mouse and keyboard deliver it: a move 40 pt right (80 px on a 2x
                // display), then Right Arrow (one pixel), then a click on the overlay window. The click also
                // proves the window takes mouse events on its clear pixels instead of passing them through.
                log.info("demo(color): app active=\(NSApp.isActive) key window=\(String(describing: NSApp.keyWindow), privacy: .public) frontmost=\(NSWorkspace.shared.frontmostApplication?.localizedName ?? "nil", privacy: .public)")
                postMouse(.mouseMoved, at: CGPoint(x: target.x + 40, y: target.y))
                postKey(124)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                    guard let self else { return }
                    log.info("demo(color): after a 40 pt move and one Right Arrow: pixel \(self.color.debugPixel, privacy: .public), value \(self.color.debugValue ?? "nothing", privacy: .public)")
                    postMouse(.leftMouseDown, at: CGPoint(x: target.x + 40, y: target.y))
                    postMouse(.leftMouseUp, at: CGPoint(x: target.x + 40, y: target.y))
                    log.info("demo(color): posted a real click")
                    colorDemoReport()
                }
            }
        }
    }

    /// What the pick left behind: the pasteboard, the newest history row and the dismissed loupe.
    private func colorDemoReport() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self else { return }
            let pasteboard = NSPasteboard.general.string(forType: .string) ?? "nothing"
            let recent = state.recent.first
            log.info("demo(color): pasteboard = \(pasteboard, privacy: .public)")
            log.info("demo(color): newest row kind=\(recent?.kind.rawValue ?? "nil", privacy: .public) text=\(recent?.text ?? "nil", privacy: .public)")
            log.info("demo(color): loupe windows after the pick = \(self.color.debugWindowCount) (must be 0)")
        }
    }

    /// `point` is AppKit global (bottom-left origin); CGEvent wants top-left.
    private func postMouse(_ type: CGEventType, at point: CGPoint) {
        let height = NSScreen.screens.first?.frame.height ?? 0
        let source = CGEventSource(stateID: .combinedSessionState)
        CGEvent(
            mouseEventSource: source, mouseType: type,
            mouseCursorPosition: CGPoint(x: point.x, y: height - point.y), mouseButton: .left
        )?.post(tap: .cghidEventTap)
    }

    private func postKey(_ keyCode: CGKeyCode, flags: CGEventFlags = []) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        down?.flags = flags
        up?.flags = flags
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
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
    #endif
}
