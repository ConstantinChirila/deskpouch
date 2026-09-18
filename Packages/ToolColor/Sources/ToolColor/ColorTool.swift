import AppKit
import DeskpouchCapture
import DeskpouchCore
import Foundation
import os

private let log = Logger(subsystem: "com.constantinchirila.deskpouch", category: "color")

/// ⌘⇧9 shows a loupe that follows the cursor; a click copies the pixel under it in the chosen format and logs it
/// (copy + history by default). Each display is captured once, when the cursor first reaches it, and sampled from
/// memory after that (`03-color.md`): a capture per mouse move is too slow.
@MainActor
public final class ColorTool: Tool {
    public let id = "color"
    public let name = "Color"
    /// Persisted under `color.hotkey`, same shape as the other press tools.
    public var pressKey: KeyCombo? {
        didSet {
            let data = pressKey.flatMap { try? JSONEncoder().encode($0) }
            UserDefaults.standard.set(data, forKey: Self.hotkeyDefaultsKey)
        }
    }
    static let hotkeyDefaultsKey = "color.hotkey"
    public var defaultOutput: ToolOutputConfig {
        ToolOutputConfig(actions: [.copy, .history])
    }

    /// Persisted on every change; an open loupe picks it up straight away.
    public var settings: ColorSettings {
        didSet {
            guard settings != oldValue else { return }
            settings.save()
            loupe?.model.settings = settings
        }
    }

    private var context: ToolContext?
    private var loupe: LoupeController?
    /// Displays with a capture in flight, so moving back and forth does not start a second one.
    private var capturing: Set<CGDirectDisplayID> = []

    public init(settings: ColorSettings = .load()) {
        self.settings = settings
        if let data = UserDefaults.standard.data(forKey: Self.hotkeyDefaultsKey),
           let combo = try? JSONDecoder().decode(KeyCombo.self, from: data) {
            pressKey = combo
        } else {
            pressKey = .commandShift9
        }
    }

    public func attach(_ context: ToolContext) {
        self.context = context
    }

    public func deactivate() {
        loupe?.cancel()
    }

    public var isOpen: Bool { loupe != nil }

    public func keyPressed() {
        if let loupe {
            loupe.cancel()
        } else {
            open()
        }
    }

    private func open() {
        guard let context else { return }
        if !Permissions.screenRecordingGranted {
            log.info("screen recording permission missing, prompting")
            guard Permissions.requestScreenRecording() else {
                context.overlay.flash(.failed("Allow Screen Recording for Deskpouch, then relaunch it"), for: .seconds(3))
                return
            }
        }
        let screens = NSScreen.screens.map {
            LoupeScreen(id: $0.displayID, frame: $0.frame, pixelsPerPoint: $0.backingScaleFactor)
        }
        let controller = LoupeController(model: LoupeModel(screens: screens, settings: settings))
        controller.onScreen = { [weak self, weak controller] screen in
            guard let controller else { return }
            self?.captureIfNeeded(screen, for: controller)
        }
        controller.onFinish = { [weak self] color in
            self?.finished(color)
        }
        loupe = controller
        controller.present()
    }

    private func captureIfNeeded(_ screen: LoupeScreen, for controller: LoupeController) {
        guard controller.model.buffers[screen.id] == nil, !capturing.contains(screen.id) else { return }
        capturing.insert(screen.id)
        Task { [weak self, weak controller] in
            defer { self?.capturing.remove(screen.id) }
            do {
                let still = try await StillCapture.display(screen.id)
                // Redrawing a 5K capture into sRGB is tens of MB of work; keep it off the main actor.
                let buffer = await Task.detached(priority: .userInitiated) {
                    PixelBuffer(image: still.image, pixelsPerPoint: still.pixelsPerPoint)
                }.value
                guard let controller, controller.isPresented else { return }
                guard let buffer else {
                    log.error("display \(screen.id) capture could not be converted to sRGB")
                    return
                }
                if abs(buffer.pixelsPerPoint - screen.pixelsPerPoint) > 0.01 {
                    log.error("display \(screen.id) captured at \(buffer.pixelsPerPoint)x, screen reports \(screen.pixelsPerPoint)x")
                }
                controller.model.setBuffer(buffer, for: screen.id)
            } catch {
                log.error("display capture failed: \(String(describing: error), privacy: .public)")
                guard let self, let controller, controller.isPresented else { return }
                controller.cancel()
                context?.overlay.flash(.failed("Screen capture unavailable"), for: .seconds(2))
            }
        }
    }

    private func finished(_ color: SRGBColor?) {
        loupe = nil
        capturing.removeAll()
        guard let color, let context else { return }
        let value = settings.format.string(for: color)
        log.info("picked \(value, privacy: .public)")
        // The exact pixel goes in the row's metadata: the text is only the format that was copied, and hsl and
        // oklch round on the way out, so History could not show the other formats faithfully from it.
        context.emit(ToolResult(toolID: id, text: value, kind: .color, meta: ResultMeta(srgb: color.clamped.hex)))
    }

    // MARK: Demo

    #if DEBUG
    /// Opens the loupe as ⌘⇧9 would and parks it on `point` (AppKit global). Verification only.
    public func debugOpen(at point: CGPoint) {
        if loupe == nil { open() }
        loupe?.follow(point)
    }

    public var debugHasSample: Bool { loupe?.model.centerColor != nil }

    public var debugValue: String? { loupe?.model.value }

    /// The pixel the loupe is reading, as "x,y".
    public var debugPixel: String {
        guard let pixel = loupe?.model.pixel else { return "none" }
        return "\(pixel.x),\(pixel.y)"
    }

    public var debugWindowCount: Int { loupe?.debugWindowCount() ?? 0 }

    public func debugSnapshot() -> NSImage? { loupe?.debugSnapshot() }

    public func debugPick() { loupe?.pick() }
    #endif
}
