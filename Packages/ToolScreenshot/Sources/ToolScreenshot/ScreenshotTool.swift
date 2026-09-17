import AppKit
import ImageIO
import DeskpouchCapture
import DeskpouchCore
import Foundation
import os

private let log = Logger(subsystem: "com.constantinchirila.deskpouch", category: "screenshot")

/// ⌘⇧2 opens the region / window / screen picker (mint `.still` style); a selection captures straight away and
/// lands in the pipeline (copy + save + history by default). The pill then offers Annotate, which opens the
/// shared editor on the delivered file; so does the hover button on screenshot rows (`annotate(fileURL:)`).
@MainActor
public final class ScreenshotTool: Tool {
    public let id = "screenshot"
    public let name = "Screenshot"
    /// Persisted under `shot.hotkey`, the same shape as the recorder's `screen.hotkey`. The shell re-registers
    /// the hotkey when it changes this.
    public var pressKey: KeyCombo? {
        didSet {
            let data = pressKey.flatMap { try? JSONEncoder().encode($0) }
            UserDefaults.standard.set(data, forKey: Self.hotkeyDefaultsKey)
        }
    }
    static let hotkeyDefaultsKey = "shot.hotkey"
    public var defaultOutput: ToolOutputConfig {
        ToolOutputConfig(actions: [.copy, .saveToFolder, .history], folder: Self.defaultFolder)
    }

    /// Persisted on every change.
    public var settings: ScreenshotSettings {
        didSet {
            guard settings != oldValue else { return }
            settings.save()
            onStatus?(settings.scale.label(nativeScale: NSScreen.main?.backingScaleFactor ?? 2))
        }
    }

    /// Scale label for the panel row/card; folder is not this tool's business, the panel reads it off the
    /// output config directly (see `ScreenToolView.folderLabel` for the same pattern on the recorder).
    public var onStatus: (@MainActor (String) -> Void)?

    private enum Phase {
        case idle
        case fetchingContent
        case picking(PickerWindowController)
        case capturing
    }

    private var phase: Phase = .idle
    private var context: ToolContext?
    /// False while switched off in General.
    private var active = true

    public init(settings: ScreenshotSettings = .load()) {
        self.settings = settings
        if let data = UserDefaults.standard.data(forKey: Self.hotkeyDefaultsKey),
           let combo = try? JSONDecoder().decode(KeyCombo.self, from: data) {
            pressKey = combo
        } else {
            pressKey = .commandShift2
        }
    }

    public func attach(_ context: ToolContext) {
        self.context = context
    }

    public func activate() {
        active = true
    }

    /// Switched off in General: an open picker is cancelled. A capture already in flight is allowed to finish
    /// (there is nothing to cancel mid-screenshot), but its result is dropped instead of emitted.
    public func deactivate() {
        active = false
        switch phase {
        case .fetchingContent:
            phase = .idle
        case .picking(let picker):
            picker.model.cancel()
        case .idle, .capturing:
            break
        }
        context?.editor.close { $0 is AnnotateDocument }
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
        case .fetchingContent, .capturing:
            break
        }
    }

    // MARK: Picker

    private func openPicker(presetRegion: CGRect? = nil) {
        guard let context else { return }
        if !Permissions.screenRecordingGranted {
            log.info("screen recording permission missing, prompting")
            guard Permissions.requestScreenRecording() else {
                context.overlay.flash(.failed("Allow Screen Recording for Deskpouch, then relaunch it"), for: .seconds(3))
                return
            }
        }
        phase = .fetchingContent
        Task { [weak self] in
            guard let self else { return }
            do {
                let content = try await ShareableContentLoader.load()
                guard case .fetchingContent = phase else { return }
                let model = ShareableContentLoader.makeModel(
                    from: content, systemAudio: false, microphone: false, frameRate: 60, style: .still
                )
                let picker = PickerWindowController(model: model)
                // Weak picker: the picker owns the model, a strong capture here would keep both alive forever.
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
        picker.dismiss()
        guard let selection else {
            phase = .idle
            return
        }
        // Claim `.capturing` synchronously, before the Task even starts: a ⌘⇧2 press landing in the gap between
        // this call and the Task's first suspension would otherwise still see `.idle` (set here previously) and
        // open a second picker, silently dropping this selection. `keyPressed()` ignores `.capturing`, so a press
        // now just does nothing until this capture finishes.
        phase = .capturing
        // No yield needed before capturing: `dismiss()` above orders the picker's overlay windows out
        // synchronously (`NSWindow.orderOut`, no animation), and the capture itself cannot see them anyway,
        // region and screen filters exclude Deskpouch's whole app, and window mode targets one window directly
        // (`desktopIndependentWindow`) with nothing else in frame.
        Task { [weak self] in
            await self?.capture(selection)
        }
    }

    // MARK: Capture

    private func capture(_ selection: PickerSelection) async {
        // `.capturing` was already set by whoever called this (the picker or a debug path); deactivate() never
        // resets it while a capture is in flight, so this only bails if something unexpected changed the phase.
        guard case .capturing = phase else { return }
        guard let context else {
            // Should not happen (`context` is set at launch), but leaving the phase at `.capturing` would wedge
            // the tool: no new picker could ever open again.
            log.error("capture() reached with no context, resetting")
            phase = .idle
            return
        }
        do {
            let still = try await StillCapture.capture(selection, scale: settings.scale, windowShadow: settings.windowShadow)
            let image = still.image
            let pixelsPerPoint = still.pixelsPerPoint
            phase = .idle
            guard active else { return }
            let staging = Self.stagingURL(for: Date())
            // Off the main actor: `CGImage` is Sendable (see `ToolResult.image`), and PNG encoding is real work
            // that has no business blocking the panel or the next hotkey press.
            try await Task.detached(priority: .utility) {
                try FileManager.default.createDirectory(at: staging.deletingLastPathComponent(), withIntermediateDirectories: true)
                try ImageWriter.write(image, to: staging, format: .png, pixelsPerPoint: pixelsPerPoint)
            }.value
            let followUp = ResultFollowUp(label: "Annotate") { [weak self] file in
                self?.annotate(fileURL: file)
            }
            context.emit(ToolResult(toolID: id, fileURL: staging, image: image, followUp: followUp))
        } catch {
            log.error("capture failed: \(String(describing: error), privacy: .public)")
            phase = .idle
            context.overlay.flash(.failed("Screenshot failed"), for: .seconds(2))
        }
    }

    // MARK: Annotate

    /// Opens the editor on a screenshot file. The export comes back through the pipeline as a new result.
    public func annotate(fileURL: URL) {
        guard let context else { return }
        let fontName = AnnotationRenderer.textFontName
        let fallbackScale = NSScreen.main?.backingScaleFactor ?? 2
        Task { [weak self] in
            // Decode, pixelate and set up the renderer off the main actor: a full-screen capture is tens of MB.
            let renderer = await Task.detached(priority: .userInitiated) { () -> AnnotationRenderer? in
                let options = [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
                guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
                      let image = CGImageSourceCreateImageAtIndex(source, 0, options) else { return nil }
                // Files from before DPI was written: assume the main screen's scale.
                let scale = ImageWriter.pixelsPerPoint(of: fileURL) ?? fallbackScale
                return AnnotationRenderer(base: image, pixelScale: max(1, scale), fontName: fontName)
            }.value
            guard let self else { return }
            guard let renderer else {
                log.error("annotate: cannot read \(fileURL.lastPathComponent, privacy: .public)")
                context.overlay.flash(.failed("That screenshot is gone"), for: .seconds(2))
                return
            }
            let document = AnnotateDocument(sourceURL: fileURL, renderer: renderer, toolID: id)
            context.editor.present(document, for: id)
            lastDocument = document
        }
    }

    /// The document last opened, for demos.
    private weak var lastDocument: AnnotateDocument?

    /// Screenshots are written to Application Support first, already named the way Save expects to find them
    /// (`Screenshot yyyy-MM-dd HH.mm.ss.png`, `01-screenshot.md`); the pipeline's Save moves the file to the
    /// user's folder, keeping that name. Not the temp folder: with Save off the file has to stay around, and
    /// macOS purges old files from $TMPDIR. Each capture gets its own UUID subfolder: the timestamp alone is
    /// only second-precision, so two captures inside the same second would otherwise target the same staging
    /// file (a fast double-press, or region and window mode racing in tests).
    static func stagingURL(for date: Date) -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Deskpouch/Screenshots", directoryHint: .isDirectory)
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
            .appending(path: CaptureNaming.stamped(prefix: "Screenshot", extension: "png", date: date))
    }

    /// `~/Pictures/Deskpouch`. The pipeline's own default folder is `~/Movies/Deskpouch` (right for the
    /// recorder, wrong here), so this tool passes its own folder into `defaultOutput` instead of relying on it.
    public static var defaultFolder: URL {
        FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask)[0]
            .appending(path: "Deskpouch", directoryHint: .isDirectory)
    }

    // MARK: Demo

    // Debug builds only: `debugCapture` grabs the screen with no picker.
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

    /// Adds sample marks to the open editor: an arrow, a box, a number badge, a blur and a text label.
    /// Verification only.
    public func debugAnnotateOpenDocument() -> Bool {
        guard let document = lastDocument else { return false }
        let size = document.renderer.imageSize
        document.model.add(Annotation(shape: .box(CGRect(x: size.width * 0.08, y: size.height * 0.12, width: size.width * 0.34, height: size.height * 0.3))))
        document.model.add(Annotation(
            shape: .arrow(from: CGPoint(x: size.width * 0.72, y: size.height * 0.7), to: CGPoint(x: size.width * 0.45, y: size.height * 0.4)),
            color: .white, size: .thick
        ))
        document.model.add(Annotation(shape: .badge(center: CGPoint(x: size.width * 0.08, y: size.height * 0.12), number: 1)))
        document.model.add(Annotation(shape: .blur(CGRect(x: size.width * 0.55, y: size.height * 0.1, width: size.width * 0.3, height: size.height * 0.2))))
        document.model.add(Annotation(
            shape: .text(origin: CGPoint(x: size.width * 0.5, y: size.height * 0.78), string: "Ship this"), color: .ink
        ))
        document.model.selection = nil
        return true
    }

    public func debugCancelPicker() {
        guard case .picking(let picker) = phase else { return }
        picker.model.cancel()
    }

    /// The open picker's model, or nil when nothing is open. Lets a demo drive a real picker session
    /// (`keyPressed()` opened it) through the same `PickerModel` calls the mouse and Return key use
    /// (`dragChanged`/`dragEnded`/`confirm`), instead of a synthetic capture that skips the picker entirely.
    /// Verification only.
    public var debugPickerModel: PickerModel? {
        guard case .picking(let picker) = phase else { return nil }
        return picker.model
    }

    /// Captures `region` of the mouse's screen (or the whole screen when nil) with no picker, through the real
    /// output pipeline. Verification only.
    public func debugCapture(region: CGRect?) {
        guard case .idle = phase else { return }
        phase = .fetchingContent
        Task { [weak self] in
            guard let self else { return }
            do {
                let content = try await ShareableContentLoader.load()
                let model = ShareableContentLoader.makeModel(
                    from: content, systemAudio: false, microphone: false, frameRate: 60, style: .still
                )
                guard let screen = model.screen(model.toolbarScreenID) else {
                    phase = .idle
                    return
                }
                phase = .capturing
                let selection: PickerSelection = region.map { .region(screen: screen, rect: $0) } ?? .screen(screen)
                await capture(selection)
            } catch {
                phase = .idle
                log.error("debug capture failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    /// Captures the frontmost normal window of another app (`ShareableContentLoader.makeModel` already excludes
    /// Deskpouch's own windows and sorts front-to-back), no picker, through the real output pipeline. Used to
    /// check window-mode sizing and the shadow option; open a target window first, e.g. `open ~` for Finder.
    /// Verification only.
    public func debugCaptureWindow() {
        guard case .idle = phase else { return }
        phase = .fetchingContent
        Task { [weak self] in
            guard let self else { return }
            do {
                let content = try await ShareableContentLoader.load()
                let model = ShareableContentLoader.makeModel(
                    from: content, systemAudio: false, microphone: false, frameRate: 60, style: .still
                )
                guard let window = model.frontmostWindow else {
                    phase = .idle
                    log.error("debug window capture: no other window is on screen")
                    return
                }
                phase = .capturing
                await capture(.window(window))
            } catch {
                phase = .idle
                log.error("debug window capture failed: \(String(describing: error), privacy: .public)")
            }
        }
    }
    #endif
}
