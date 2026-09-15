import AppKit
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
    public let pressKey: KeyCombo? = .commandShift6
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

    /// Recordings shorter than this are dropped as accidental.
    static let minimumDuration: TimeInterval = 0.5

    public init(settings: RecorderSettings = .load()) {
        self.settings = settings
        recorder.onStreamStopped = { [weak self] _ in
            // Window closed, display unplugged or the grant was pulled: finalise whatever was written.
            self?.stopRecording()
        }
    }

    public func attach(_ context: ToolContext) {
        self.context = context
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
                content = try await Self.shareableContent()
                guard case .fetchingContent = phase, let content else { return }
                let model = makeModel(from: content)
                let picker = PickerWindowController(model: model)
                model.onFinish = { [weak self] selection in
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

    private static func ownApplication(fallback: SCShareableContent) async -> SCRunningApplication? {
        let pid = ProcessInfo.processInfo.processIdentifier
        if let own = try? await SCShareableContent.currentProcess, let app = own.applications.first(where: { $0.processID == pid }) {
            return app
        }
        return fallback.applications.first { $0.processID == pid }
    }

    private static func shareableContent() async throws -> SCShareableContent {
        try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
    }

    /// Screens from AppKit, windows from ScreenCaptureKit in front-to-back order, toolbar on the mouse's screen.
    private func makeModel(from content: SCShareableContent) -> PickerModel {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let mouse = NSEvent.mouseLocation
        var toolbarScreenID = 0
        let screens = NSScreen.screens.enumerated().map { index, screen in
            let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            if screen.frame.contains(mouse) { toolbarScreenID = index }
            return PickerScreen(
                id: index,
                displayID: CGDirectDisplayID(number?.uint32Value ?? 0),
                frame: screen.frame,
                cgFrame: CGRect(x: screen.frame.minX, y: primaryHeight - screen.frame.maxY,
                                width: screen.frame.width, height: screen.frame.height),
                backingScale: screen.backingScaleFactor
            )
        }

        let order = Self.windowZOrder()
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let windows = content.windows
            .filter { window in
                window.isOnScreen && window.windowLayer == 0
                    && window.owningApplication?.processID != ownPID
                    && window.frame.width >= 40 && window.frame.height >= 40
            }
            .sorted { (order[$0.windowID] ?? .max) < (order[$1.windowID] ?? .max) }
            .map { window in
                PickerWindow(
                    id: window.windowID, frame: window.frame,
                    title: window.title ?? "", appName: window.owningApplication?.applicationName ?? ""
                )
            }

        return PickerModel(
            screens: screens, windows: windows, toolbarScreenID: toolbarScreenID,
            systemAudio: settings.systemAudio, microphone: settings.microphone, frameRate: settings.frameRate
        )
    }

    /// Window id to z index, front-most first. ScreenCaptureKit's list has no documented order.
    private static func windowZOrder() -> [CGWindowID: Int] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] else { return [:] }
        var order: [CGWindowID: Int] = [:]
        for (index, info) in list.enumerated() {
            if let number = info[kCGWindowNumber as String] as? NSNumber {
                order[CGWindowID(number.uint32Value)] = index
            }
        }
        return order
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
            displayPoints: screen.frame.size, backingScale: screen.backingScale, quality: settings.quality
        )
        // The general content list leaves out apps without regular windows, Deskpouch included, so the exclusion
        // that keeps the pill out of the recording has to come from the current-process query.
        let ownApp = await Self.ownApplication(fallback: content)
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
        let since = recorder.startedAt ?? Date()
        context.overlay.showRecording(
            detail: CaptureGeometry.detail(points: target.pointSize, frameRate: settings.frameRate), since: since
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

    /// Recordings land in a temp folder; the output pipeline's Save moves them to the user's folder.
    static func stagingURL(for date: Date) -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "Deskpouch", directoryHint: .isDirectory)
            .appending(path: "Recording \(fileStamp.string(from: date)).mp4")
    }

    private static let fileStamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return f
    }()

    // MARK: Demo

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
                content = try await Self.shareableContent()
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
}
