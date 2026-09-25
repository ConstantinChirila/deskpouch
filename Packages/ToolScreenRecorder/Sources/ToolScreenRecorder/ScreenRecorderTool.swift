import AVFoundation
import AppKit
import DeskpouchCapture
import DeskpouchCore
import Foundation
import ScreenCaptureKit
import os

private let log = Logger(subsystem: "com.constantinchirila.deskpouch", category: "screen")

/// ⌘⇧6 opens the region / window / screen picker; Record starts a ScreenCaptureKit recording straight to mp4.
/// The same key, the menubar icon or the pill's Stop button ends it and the file is emitted as a `ToolResult`.
/// The pill then offers Trim, which opens the shared editor on the delivered file; so does the hover button on
/// recording rows (`trim(fileURL:)`).
@MainActor
public final class ScreenRecorderTool: Tool {
    public let id = "screen"
    public let name = "Record screen"
    /// Persisted under `screen.hotkey`. The shell re-registers the hotkey when it changes this.
    public var pressKey: KeyCombo? {
        didSet {
            let data = pressKey.flatMap { try? JSONEncoder().encode($0) }
            UserDefaults.standard.set(data, forKey: Self.hotkeyDefaultsKey)
        }
    }
    static let hotkeyDefaultsKey = "screen.hotkey"
    public let defaultOutput = ToolOutputConfig(actions: [.saveToFolder, .copy, .notify, .history])

    /// Persisted on every change. The picker's audio toggles write through here.
    public var settings: RecorderSettings {
        didSet {
            guard settings != oldValue else { return }
            settings.save()
            onStatus?(settings.summary)
        }
    }

    /// "1080p · system audio" line for the panel card.
    public var onStatus: (@MainActor (String) -> Void)?

    private enum Phase {
        case idle
        case fetchingContent
        case picking(PickerWindowController)
        case starting
        case recording
        case stopping
    }

    private var phase: Phase = .idle
    private let recorder = ScreenRecorder()
    private var context: ToolContext?
    private var maxLengthTimer: Timer?
    /// Stops the recorder and hands the file on. Kept so a quit can wait for it.
    private var stopTask: Task<Void, Never>?
    /// Displays, windows and apps as of the last picker session; the recording resolves its target here.
    private var content: SCShareableContent?
    /// False while switched off in General.
    private var active = true

    /// Recordings shorter than this are dropped as accidental.
    static let minimumDuration: TimeInterval = 0.5

    public init(settings: RecorderSettings = .load()) {
        self.settings = settings
        if let data = UserDefaults.standard.data(forKey: Self.hotkeyDefaultsKey),
           let combo = try? JSONDecoder().decode(KeyCombo.self, from: data) {
            pressKey = combo
        } else {
            pressKey = .commandShift6
        }
        recorder.onStreamStopped = { [weak self] _ in
            // Window closed, display unplugged or the grant was pulled: finalise whatever was written.
            self?.stopRecording()
        }
        recorder.onOutputFailed = { [weak self] _ in
            // Disk full or an encoder error: nothing more is being written, so the recording ends here instead
            // of counting on with nothing behind it.
            self?.stopRecording()
        }
    }

    public func attach(_ context: ToolContext) {
        self.context = context
    }

    public func activate() {
        active = true
    }

    /// Switched off in General: a picker closes, a recording stops and is delivered as usual. A recording that is
    /// still starting stops as soon as it is running.
    public func deactivate() {
        active = false
        switch phase {
        case .fetchingContent:
            phase = .idle
        case .picking(let picker):
            picker.model.cancel()
        case .recording:
            stopRecording()
        case .idle, .starting, .stopping:
            break
        }
        context?.editor.close { $0 is TrimDocument }
    }

    public var isRecording: Bool {
        if case .recording = phase { return true }
        return false
    }

    public var isPicking: Bool {
        if case .picking = phase { return true }
        return false
    }

    public func keyPressed() {
        switch phase {
        case .idle:
            openPicker()
        case .picking(let picker):
            picker.model.cancel()
        case .recording:
            stopRecording()
        case .fetchingContent, .starting, .stopping:
            break
        }
    }

    // MARK: Picker

    private func openPicker(presetRegion: CGRect? = nil) {
        guard let context else { return }
        if !Permissions.screenRecordingGranted {
            log.info("screen recording permission missing, prompting")
            // Shows the system prompt the first time. macOS usually wants a relaunch after the grant.
            guard Permissions.requestScreenRecording() else {
                context.overlay.flash(.failed("Allow Screen Recording for Deskpouch, then relaunch it"), for: .seconds(3))
                return
            }
        }
        phase = .fetchingContent
        Task { [weak self] in
            guard let self else { return }
            do {
                content = try await ShareableContentLoader.load()
                guard case .fetchingContent = phase, let content else { return }
                let model = makeModel(from: content)
                let picker = PickerWindowController(model: model)
                // Weak picker: the picker owns the model, so a strong capture here would keep both alive forever.
                model.onFinish = { [weak self, weak picker] selection in
                    guard let picker else { return }
                    self?.pickerFinished(selection, picker: picker)
                }
                if let presetRegion, let screen = model.screen(model.toolbarScreenID) {
                    model.dragChanged(screenID: screen.id, location: presetRegion.origin)
                    model.dragChanged(screenID: screen.id, location: CGPoint(x: presetRegion.maxX, y: presetRegion.maxY))
                    model.dragEnded(screenID: screen.id, location: CGPoint(x: presetRegion.maxX, y: presetRegion.maxY))
                }
                phase = .picking(picker)
                picker.present()
            } catch {
                log.error("shareable content failed: \(String(describing: error), privacy: .public)")
                phase = .idle
                context.overlay.flash(.failed("Screen capture unavailable"), for: .seconds(2))
            }
        }
    }

    private func pickerFinished(_ selection: PickerSelection?, picker: PickerWindowController) {
        settings.systemAudio = picker.model.systemAudio
        settings.microphone = picker.model.microphone
        picker.dismiss()
        guard let selection else {
            phase = .idle
            content = nil
            return
        }
        // Claim `.starting` synchronously, before the Task even starts: a ⌘⇧6 press landing in the gap between
        // this call and the Task's first suspension would otherwise still see `.idle` (set here previously) and
        // open a second picker, silently dropping this selection. `keyPressed()` ignores `.starting`, so a press
        // now just does nothing until this recording has started.
        phase = .starting
        Task { [weak self] in
            await self?.start(selection, screens: picker.model.screens)
        }
    }

    private func makeModel(from content: SCShareableContent) -> PickerModel {
        ShareableContentLoader.makeModel(
            from: content, systemAudio: settings.systemAudio, microphone: settings.microphone, frameRate: settings.frameRate
        )
    }

    // MARK: Recording

    private func start(_ selection: PickerSelection, screens: [PickerScreen]) async {
        // `.starting` was already set by `pickerFinished`, before the Task even started; deactivate() never
        // resets it while starting, so this only bails if something unexpected changed the phase.
        guard case .starting = phase else { return }
        guard let context, let content else {
            // Should not happen (`content` is set right before this phase and `context` at launch), but leaving
            // the phase at `.starting` would wedge the tool: no picker can reopen and no recording ever starts.
            log.error("start() reached with context=\(self.context != nil) content=\(self.content != nil), resetting")
            phase = .idle
            self.content = nil
            return
        }
        defer { self.content = nil }

        let target: CaptureTarget
        let screen: PickerScreen
        switch selection {
        case .region(let s, let rect):
            guard let display = content.displays.first(where: { $0.displayID == s.displayID }) else {
                return fail("Display not found")
            }
            target = .display(display, region: rect)
            screen = s
        case .screen(let s):
            guard let display = content.displays.first(where: { $0.displayID == s.displayID }) else {
                return fail("Display not found")
            }
            target = .display(display, region: nil)
            screen = s
        case .window(let w):
            guard let window = content.windows.first(where: { $0.windowID == w.id }) else {
                return fail("Window is gone")
            }
            target = .window(window)
            let centre = CGPoint(x: w.frame.midX, y: w.frame.midY)
            screen = screens.first { $0.cgFrame.contains(centre) } ?? screens[0]
        }

        var microphone = settings.microphone
        if microphone, Permissions.microphone == .undetermined {
            microphone = await Permissions.requestMicrophone()
        } else if microphone, Permissions.microphone == .denied {
            microphone = false
        }

        let pixelsPerPoint = CaptureGeometry.pixelsPerPoint(
            displayPoints: screen.frame.size, backingScale: screen.backingScale, maxHeight: settings.quality.maxPixelHeight
        )
        // The general content list leaves out apps without regular windows, Deskpouch included, so the exclusion
        // that keeps the pill out of the recording has to come from the current-process query.
        let ownApp = await ShareableContentLoader.ownApplication(fallback: content)
        log.info("own app for exclusion: \(ownApp != nil)")
        let url = Self.stagingURL(for: Date())
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try await recorder.start(
                target: target, settings: settings, pixelsPerPoint: pixelsPerPoint,
                excluding: ownApp, microphone: microphone, outputURL: url
            )
        } catch {
            log.error("start failed: \(String(describing: error), privacy: .public)")
            return fail("Recording failed to start")
        }

        phase = .recording
        // Switched off meanwhile, or the output already failed while the capture was starting.
        guard active, !recorder.hasFailed else { return stopRecording() }
        let since = recorder.startedAt ?? Date()
        context.overlay.showRecording(
            detail: Self.pillDetail(points: target.pointSize, frameRate: settings.frameRate), since: since
        ) { [weak self] in
            self?.stopRecording()
        }
        context.report(.recording(since: since), from: id)
        if settings.maxMinutes > 0 {
            maxLengthTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(settings.maxMinutes * 60), repeats: false) { [weak self] _ in
                MainActor.assumeIsolated {
                    log.info("max length reached, stopping")
                    self?.stopRecording()
                }
            }
        }
    }

    public func stopRecording() {
        guard let context, case .recording = phase else { return }
        phase = .stopping
        maxLengthTimer?.invalidate()
        maxLengthTimer = nil
        context.overlay.show(.preparing("Saving recording"))
        context.report(.idle, from: id)
        stopTask = Task { [weak self] in
            guard let self else { return }
            do {
                let recording = try await recorder.stop()
                phase = .idle
                let attributes = try? FileManager.default.attributesOfItem(atPath: recording.url.path)
                let size = (attributes?[.size] as? NSNumber)?.intValue ?? 0
                var duration = recording.duration
                if let problem = recording.problem {
                    // Never announced as a plain success: what is on disk is checked, and the pill says so.
                    guard size > 0, let playable = await Self.playableDuration(of: recording.url) else {
                        log.error("recording unusable after \(String(describing: problem), privacy: .public): \(recording.url.path, privacy: .public)")
                        // A failed output wrote nothing worth keeping. An unfinalised file stays where it is: it
                        // may still be completed or repaired.
                        if case .outputFailed = problem { Self.removeStaging(recording.url) }
                        context.overlay.flash(.failed("Recording failed, nothing could be saved"), for: .seconds(3))
                        return
                    }
                    duration = playable
                    context.overlay.flash(.failed("Recording stopped early, keeping what was written"), for: .seconds(3))
                    try? await Task.sleep(for: .seconds(3))
                }
                guard duration >= Self.minimumDuration, size > 0 else {
                    log.info("dropping recording: \(duration)s, \(size) bytes")
                    Self.removeStaging(recording.url)
                    context.overlay.flash(.failed("Nothing recorded"))
                    return
                }
                let followUp = ResultFollowUp(label: "Trim") { [weak self] file in
                    self?.trim(fileURL: file)
                }
                context.emit(ToolResult(toolID: id, fileURL: recording.url, duration: duration, followUp: followUp))
            } catch {
                log.error("stop failed: \(String(describing: error), privacy: .public)")
                phase = .idle
                context.overlay.flash(.failed("Recording failed"), for: .seconds(2))
            }
        }
    }

    /// Quit: ends a recording that is running (or still starting) and returns once its file has been handed on.
    public func finishRecording() async {
        while case .starting = phase { try? await Task.sleep(for: .milliseconds(50)) }
        stopRecording()
        await stopTask?.value
    }

    /// True from the picker's Record until the file has been handed on.
    public var hasRecordingInProgress: Bool {
        switch phase {
        case .starting, .recording, .stopping: true
        case .idle, .fetchingContent, .picking: false
        }
    }

    /// How much of `file` plays, nil when it cannot be opened as a movie at all.
    private static func playableDuration(of file: URL) async -> TimeInterval? {
        let asset = AVURLAsset(url: file)
        guard let (playable, duration) = try? await asset.load(.isPlayable, .duration), playable, duration.isNumeric else { return nil }
        return duration.seconds
    }

    /// The staging file and the UUID folder made for it.
    private static func removeStaging(_ file: URL) {
        try? FileManager.default.removeItem(at: file.deletingLastPathComponent())
    }

    // MARK: Trim

    /// Opens the editor on a recording. The export comes back through the pipeline as a new result.
    public func trim(fileURL: URL) {
        guard let context else { return }
        Task { [weak self] in
            // Duration, size and frame rate are read off the main actor before the window opens.
            let media = try? await TrimDocument.Media.load(fileURL)
            guard let self else { return }
            guard let media else {
                log.error("trim: cannot read \(fileURL.lastPathComponent, privacy: .public)")
                context.overlay.flash(.failed("That recording is gone"), for: .seconds(2))
                return
            }
            let document = TrimDocument(sourceURL: fileURL, media: media, toolID: id)
            context.editor.present(document, for: id)
            lastDocument = document
        }
    }

    /// The document last opened, for demos.
    private weak var lastDocument: TrimDocument?

    private func fail(_ message: String) {
        phase = .idle
        context?.overlay.flash(.failed(message), for: .seconds(2))
    }

    /// Recordings are written to Application Support; the output pipeline's Save moves them to the user's folder.
    /// Not the temp folder: with Save off the file stays here, and macOS purges old files from $TMPDIR. Each
    /// recording gets its own UUID subfolder so two recordings starting in the same second (the timestamp is
    /// only second-precision) never target the same staging file.
    static func stagingURL(for date: Date) -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Deskpouch/Recordings", directoryHint: .isDirectory)
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
            .appending(path: CaptureNaming.stamped(prefix: "Recording", extension: "mp4", date: date))
    }

    /// "1040 × 760 · 60 fps" for the recording pill.
    static func pillDetail(points: CGSize, frameRate: Int) -> String {
        "\(CaptureGeometry.dimensionLabel(points)) · \(frameRate) fps"
    }

    // MARK: Demo

    // Debug builds only: `debugRecord` captures the screen with no picker.
    #if DEBUG

    /// Opens the picker with a region already drawn. Design review only.
    public func debugOpenPicker(region: CGRect) {
        guard case .idle = phase else { return }
        openPicker(presetRegion: region)
    }

    public func debugSnapshotPicker() -> NSImage? {
        guard case .picking(let picker) = phase else { return nil }
        return picker.debugSnapshot()
    }

    /// Records `region` of the mouse's screen for `seconds` without the picker, then stops and emits as usual.
    /// The result goes through the real output pipeline. Verification only.
    public func debugRecord(region: CGRect?, seconds: TimeInterval) {
        guard case .idle = phase else { return }
        phase = .fetchingContent
        Task { [weak self] in
            guard let self else { return }
            do {
                content = try await ShareableContentLoader.load()
                guard let content else { return }
                let model = makeModel(from: content)
                guard let screen = model.screen(model.toolbarScreenID) else { return }
                phase = .starting
                await start(region.map { .region(screen: screen, rect: $0) } ?? .screen(screen), screens: model.screens)
                try? await Task.sleep(for: .seconds(seconds))
                stopRecording()
            } catch {
                phase = .idle
                log.error("debug record failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    /// Cuts `seconds` off each side of the open Trim document and picks the format, through the same calls the
    /// handles and the format chip make. Returns the kept length, nil when no document is open. Verification only.
    public func debugTrimOpenDocument(cutting seconds: TimeInterval, gif: Bool) -> TimeInterval? {
        guard let document = lastDocument else { return nil }
        document.dragStart(to: seconds)
        document.dragEnd(to: document.model.duration - seconds)
        document.handleDragFinished()
        document.format = gif ? .gif : .mp4
        return document.model.selectedDuration
    }

    public func debugCancelPicker() {
        guard case .picking(let picker) = phase else { return }
        picker.model.cancel()
    }
    #endif
}
