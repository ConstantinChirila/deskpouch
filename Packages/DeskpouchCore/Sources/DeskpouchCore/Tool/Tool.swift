import Foundation

/// A capture tool hosted by the shell. Voice acts on a modifier hold, the recorder on a key combo press;
/// a tool implements whichever it declares and leaves the other defaults alone.
@MainActor
public protocol Tool: AnyObject {
    var id: String { get }
    var name: String { get }
    /// Hold-to-act modifier key. The shell registers it and forwards begin/end.
    var holdKey: ModifierKey? { get }
    /// Press-to-act key combo. The shell registers it and forwards presses.
    var pressKey: KeyCombo? { get }
    /// After-capture actions the tool wants until the user changes them in the panel.
    var defaultOutput: ToolOutputConfig { get }

    func attach(_ context: ToolContext)
    func holdBegan()
    func holdEnded()
    func keyPressed()
}

public extension Tool {
    var holdKey: ModifierKey? { nil }
    var pressKey: KeyCombo? { nil }
    func holdBegan() {}
    func holdEnded() {}
    func keyPressed() {}
}

/// What a tool is doing right now, for the menubar icon and the panel.
public enum ToolActivity: Sendable, Equatable {
    case idle
    /// A long-running capture with a visible timer.
    case recording(since: Date)
}

/// What the shell hands a tool: the overlay to draw in, a way to emit results, and a way to report activity.
@MainActor
public final class ToolContext {
    public let overlay: OverlayController
    private let emitHandler: @MainActor (ToolResult) -> Void
    private let activityHandler: @MainActor (String, ToolActivity) -> Void

    public init(
        overlay: OverlayController,
        emit: @escaping @MainActor (ToolResult) -> Void,
        activity: @escaping @MainActor (String, ToolActivity) -> Void = { _, _ in }
    ) {
        self.overlay = overlay
        self.emitHandler = emit
        self.activityHandler = activity
    }

    public func emit(_ result: ToolResult) {
        emitHandler(result)
    }

    public func report(_ activity: ToolActivity, from toolID: String) {
        activityHandler(toolID, activity)
    }
}

/// Output of one capture. Text, a file, or both.
public struct ToolResult: Sendable, Identifiable {
    public let id: UUID
    public let toolID: String
    public let text: String?
    public let fileURL: URL?
    public let createdAt: Date
    /// Length of the captured audio or video, when known.
    public let duration: TimeInterval?

    public init(toolID: String, text: String? = nil, fileURL: URL? = nil, duration: TimeInterval? = nil) {
        id = UUID()
        self.toolID = toolID
        self.text = text
        self.fileURL = fileURL
        createdAt = Date()
        self.duration = duration
    }
}
