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
            if let combo = tool.pressKey {
                let registered = hotkeys.registerPress(combo) { [weak tool] in tool?.keyPressed() }
                if !registered {
                    log.error("\(combo.display, privacy: .public) is taken by another app")
                    if tool.id == screen.id { state.screenKeyTaken = true }
                }
            }
            if let key = tool.holdKey {
                hotkeys.registerHold(key) { [weak self, weak tool] phase in
                    guard let self, let tool else { return }
                    switch phase {
                    case .pressed:
                        state.isListening = true
                        statusItem.beginListening()
                        tool.holdBegan()
                    case .released:
                        state.isListening = false
                        statusItem.showIdle()
                        tool.holdEnded()
                    }
                }
            }
        }
        overlay.onLevel = { [weak self] level, dt in
            guard let self else { return }
            statusItem.push(level: level, dt: dt)
            state.panelMeter.push(level: level, dt: dt)
        }
        voice.onStatus = { [weak self] text in
            self?.state.voiceStatus = text
        }
        state.holdKey = voice.holdKey ?? .rightOption
        state.screenKey = screen.pressKey ?? .commandShift6
        state.screenStatus = screen.settings.summary
        screen.onStatus = { [weak self] text in
            self?.state.screenStatus = text
        }
        statusItem.onClick = { [weak self] button in
            guard let self else { return }
            // While recording the icon is the stop button; the panel is not reachable until the recording ends.
            if screen.isRecording {
                screen.stopRecording()
            } else {
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

    // MARK: Activity

    private func activityChanged(_ activity: ToolActivity) {
        state.activity = activity
        recordingTimer?.invalidate()
        recordingTimer = nil
        switch activity {
        case .idle:
            statusItem.showIdle()
        case .recording(let since):
            panel.close()
            statusItem.showRecording(elapsed: Date().timeIntervalSince(since))
            recordingTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.statusItem.showRecording(elapsed: Date().timeIntervalSince(since))
                }
            }
        }
    }

    // MARK: Output

    private func deliver(_ result: ToolResult) {
        Task { [weak self] in
            guard let self else { return }
            let config = state.output.config(for: result.toolID)
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
                        let aside = CGPoint(x: centre.x - 300, y: centre.y + 40)
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
