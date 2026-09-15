import Foundation

/// A capture tool hosted by the shell. Starts minimal; the second tool reshapes it.
@MainActor
public protocol Tool: AnyObject {
    var id: String { get }
    var name: String { get }
    /// Hold-to-act modifier key. The shell registers it and forwards begin/end.
    var holdKey: ModifierKey? { get }

    func attach(_ context: ToolContext)
    func holdBegan()
    func holdEnded()
}

/// What the shell hands a tool: the overlay to draw in and a way to emit results.
@MainActor
public final class ToolContext {
    public let overlay: OverlayController
    private let emitHandler: @MainActor (ToolResult) -> Void

    public init(overlay: OverlayController, emit: @escaping @MainActor (ToolResult) -> Void) {
        self.overlay = overlay
        self.emitHandler = emit
    }

    public func emit(_ result: ToolResult) {
        emitHandler(result)
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
