import CoreGraphics
import Foundation
import Observation

public enum PickerMode: String, CaseIterable, Sendable {
    case region, window, screen

    public var label: String {
        switch self {
        case .region: "Region"
        case .window: "Window"
        case .screen: "Screen"
        }
    }
}

/// One display as the picker sees it. `frame` is AppKit global (bottom-left origin); `cgFrame` is Core Graphics
/// global (top-left origin), which is also what ScreenCaptureKit uses. Local points are top-left within the screen.
public struct PickerScreen: Identifiable, Equatable, Sendable {
    public let id: Int
    public let displayID: CGDirectDisplayID
    public let frame: CGRect
    public let cgFrame: CGRect
    public let backingScale: CGFloat

    public var localBounds: CGRect { CGRect(origin: .zero, size: frame.size) }

    public func cgPoint(fromLocal point: CGPoint) -> CGPoint {
        CGPoint(x: cgFrame.minX + point.x, y: cgFrame.minY + point.y)
    }

    public func localRect(fromCG rect: CGRect) -> CGRect {
        rect.offsetBy(dx: -cgFrame.minX, dy: -cgFrame.minY)
    }
}

/// A window the picker can target. `frame` is Core Graphics global. Front-most first in the model's list.
public struct PickerWindow: Identifiable, Equatable, Sendable {
    public let id: CGWindowID
    public let frame: CGRect
    public let title: String
    public let appName: String
}

public enum PickerSelection: Equatable, Sendable {
    /// `rect` is screen-local points, top-left origin.
    case region(screen: PickerScreen, rect: CGRect)
    case window(PickerWindow)
    case screen(PickerScreen)

    public var pointSize: CGSize {
        switch self {
        case .region(_, let rect): rect.size
        case .window(let window): window.frame.size
        case .screen(let screen): screen.frame.size
        }
    }
}

/// Picker state: mode, the drag in progress, the hovered window or screen, audio toggles. Pure so it can be tested;
/// the views feed it local points and the window controller feeds it keys.
@MainActor
@Observable
public final class PickerModel {
    static let minimumRegion: CGFloat = 8
    static let snapAspect: CGFloat = 16.0 / 9.0

    public var mode: PickerMode
    public let screens: [PickerScreen]
    var windows: [PickerWindow]
    /// Screen that shows the toolbar: the one under the mouse when the picker opened.
    public let toolbarScreenID: Int
    /// Tint and toolbar label for the tool that opened the picker. Defaults to the recorder's look.
    public let style: PickerStyle
    public var systemAudio: Bool
    public var microphone: Bool
    var frameRate: Int
    /// Shift held: regions snap to 16:9.
    var snapToAspect = false

    private(set) var region: (screenID: Int, rect: CGRect)?
    private(set) var hoveredWindow: PickerWindow?
    private(set) var hoveredScreenID: Int?

    @ObservationIgnored private var drag: Drag?
    @ObservationIgnored public var onFinish: (@MainActor (PickerSelection?) -> Void)?
    @ObservationIgnored private var finished = false

    private struct Drag {
        let screenID: Int
        let anchor: CGPoint
        /// Set when the drag started inside the existing region: it moves instead of redrawing.
        let moveOffset: CGPoint?
        var moved = false
    }

    public init(
        mode: PickerMode = .region, screens: [PickerScreen], windows: [PickerWindow] = [],
        toolbarScreenID: Int, systemAudio: Bool, microphone: Bool, frameRate: Int, style: PickerStyle = .record
    ) {
        self.mode = mode
        self.screens = screens
        self.windows = windows
        self.toolbarScreenID = toolbarScreenID
        self.systemAudio = systemAudio
        self.microphone = microphone
        self.frameRate = frameRate
        self.style = style
    }

    public func screen(_ id: Int) -> PickerScreen? { screens.first { $0.id == id } }

    /// Front-most normal window of another app, or nil with nothing else on screen. `windows` is already
    /// front-to-back and excludes Deskpouch's own windows (`ShareableContentLoader.makeModel`). Verification only.
    public var frontmostWindow: PickerWindow? { windows.first }

    // MARK: Selection

    var selection: PickerSelection? {
        switch mode {
        case .region:
            guard let region, let screen = screen(region.screenID),
                  region.rect.width >= Self.minimumRegion, region.rect.height >= Self.minimumRegion else { return nil }
            return .region(screen: screen, rect: region.rect)
        case .window:
            return hoveredWindow.map { .window($0) }
        case .screen:
            return hoveredScreenID.flatMap(screen).map { .screen($0) }
        }
    }

    var canRecord: Bool { selection != nil }

    /// Region rect in a screen's local coordinates, if it lives on that screen.
    func regionRect(on screenID: Int) -> CGRect? {
        guard let region, region.screenID == screenID else { return nil }
        return region.rect
    }

    /// The hovered window's rect in a screen's local coordinates, clipped to that screen.
    func hoveredWindowRect(on screenID: Int) -> CGRect? {
        guard mode == .window, let hoveredWindow, let screen = screen(screenID) else { return nil }
        let local = screen.localRect(fromCG: hoveredWindow.frame).intersection(screen.localBounds)
        return local.isNull || local.isEmpty ? nil : local
    }

    /// "1040 × 760" for the current selection.
    var dimensionLabel: String? {
        selection.map { CaptureGeometry.dimensionLabel($0.pointSize) }
    }

    func setMode(_ newMode: PickerMode) {
        guard mode != newMode else { return }
        mode = newMode
        drag = nil
    }

    // MARK: Mouse

    public func dragChanged(screenID: Int, location: CGPoint) {
        guard mode == .region, let screen = screen(screenID) else { return }
        let point = clamp(location, to: screen.localBounds)
        if drag == nil {
            var moveOffset: CGPoint?
            if let region, region.screenID == screenID, region.rect.contains(point) {
                moveOffset = CGPoint(x: point.x - region.rect.minX, y: point.y - region.rect.minY)
            }
            drag = Drag(screenID: screenID, anchor: point, moveOffset: moveOffset)
            return
        }
        guard var drag, drag.screenID == screenID else { return }
        drag.moved = true
        self.drag = drag
        if let offset = drag.moveOffset, let current = region?.rect {
            let moved = CGRect(x: point.x - offset.x, y: point.y - offset.y, width: current.width, height: current.height)
            region = (screenID, CaptureGeometry.integral(CaptureGeometry.clamped(moved, to: screen.localBounds)))
        } else {
            let rect = CaptureGeometry.rect(from: drag.anchor, to: point, aspect: snapToAspect ? Self.snapAspect : nil)
            region = (screenID, CaptureGeometry.integral(CaptureGeometry.clamped(rect, to: screen.localBounds)))
        }
    }

    /// Mouse up. In window and screen mode a click confirms the hovered target; in region mode a double-click
    /// inside the region confirms it, like the Capture button. `clickCount` is the event's, 2 for the second click.
    public func dragEnded(screenID: Int, location: CGPoint, clickCount: Int = 1) {
        defer { drag = nil }
        switch mode {
        case .region:
            if let drag, !drag.moved, drag.moveOffset != nil, clickCount >= 2 {
                confirm()
                return
            }
            if let drag, !drag.moved, drag.moveOffset == nil { region = nil }
            if let region, region.rect.width < Self.minimumRegion || region.rect.height < Self.minimumRegion {
                self.region = nil
            }
        case .window, .screen:
            hoverChanged(screenID: screenID, location: location)
            if canRecord { confirm() }
        }
    }

    func hoverChanged(screenID: Int, location: CGPoint?) {
        guard let location, let screen = screen(screenID) else {
            if hoveredScreenID == screenID { hoveredScreenID = nil }
            return
        }
        hoveredScreenID = screenID
        let cg = screen.cgPoint(fromLocal: location)
        hoveredWindow = windows.first { $0.frame.contains(cg) }
    }

    // MARK: Keys and buttons

    public func confirm() {
        guard !finished, let selection else { return }
        finished = true
        onFinish?(selection)
    }

    public func cancel() {
        guard !finished else { return }
        finished = true
        onFinish?(nil)
    }

    private func clamp(_ point: CGPoint, to bounds: CGRect) -> CGPoint {
        CGPoint(x: min(max(point.x, bounds.minX), bounds.maxX), y: min(max(point.y, bounds.minY), bounds.maxY))
    }
}
