import AppKit
import DeskpouchCapture
import DeskpouchCore
import Foundation
import ScreenCaptureKit
import os

private let log = Logger(subsystem: "com.constantinchirila.deskpouch", category: "screen")

/// ⌘⇧6 opens the region / window / screen picker; Record starts a ScreenCaptureKit recording straight to mp4.
/// The same key, the menubar icon or the pill's Stop button ends it and the file is emitted as a `ToolResult`.
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
        phase = .idle
        guard let selection else {
            content = nil
            return
        }
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
        guard let context, let content, case .idle = phase else { return }
        phase = .starting
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
        guard active else { return stopRecording() }
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
        Task { [weak self] in
            guard let self else { return }
            do {
                let recording = try await recorder.stop()
                phase = .idle
                let attributes = try? FileManager.default.attributesOfItem(atPath: recording.url.path)
                let size = (attributes?[.size] as? NSNumber)?.intValue ?? 0
                guard recording.duration >= Self.minimumDuration, size > 0 else {
                    log.info("dropping recording: \(recording.duration)s, \(size) bytes")
                    try? FileManager.default.removeItem(at: recording.url)
                    context.overlay.flash(.failed("Nothing recorded"))
                    return
                }
                context.emit(ToolResult(toolID: id, fileURL: recording.url, duration: recording.duration))
            } catch {
                log.error("stop failed: \(String(describing: error), privacy: .public)")
                phase = .idle
                context.overlay.flash(.failed("Recording failed"), for: .seconds(2))
            }
        }
    }

    private func fail(_ message: String) {
        phase = .idle
        context?.overlay.flash(.failed(message), for: .seconds(2))
    }

    /// Recordings are written to Application Support; the output pipeline's Save moves them to the user's folder.
    /// Not the temp folder: with Save off the file stays here, and macOS purges old files from $TMPDIR.
    static func stagingURL(for date: Date) -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Deskpouch/Recordings", directoryHint: .isDirectory)
            .appending(path: "Recording \(fileStamp.string(from: date)).mp4")
    }

    /// "1040 × 760 · 60 fps" for the recording pill.
    static func pillDetail(points: CGSize, frameRate: Int) -> String {
        "\(CaptureGeometry.dimensionLabel(points)) · \(frameRate) fps"
    }

    private static let fileStamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return f
    }()

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
                phase = .idle
                await start(region.map { .region(screen: screen, rect: $0) } ?? .screen(screen), screens: model.screens)
                try? await Task.sleep(for: .seconds(seconds))
                stopRecording()
            } catch {
                phase = .idle
                log.error("debug record failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    public func debugCancelPicker() {
        guard case .picking(let picker) = phase else { return }
        picker.model.cancel()
    }
    #endif
}
