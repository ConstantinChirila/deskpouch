import CoreGraphics
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

    /// Called once at launch, whether or not the tool is switched on.
    func attach(_ context: ToolContext)
    /// Switched on, at launch or later from General. Load what the first use should not wait for.
    func activate()
    /// Switched off in General. The shell has already dropped the hotkeys; end any capture in progress and let go
    /// of what `activate` loaded.
    func deactivate()
    func holdBegan()
    func holdEnded()
    /// The hold turned out to be part of a key chord. Drop whatever it started, emit nothing.
    func holdCancelled()
    func keyPressed()
}

public extension Tool {
    var holdKey: ModifierKey? { nil }
    var pressKey: KeyCombo? { nil }
    func activate() {}
    func deactivate() {}
    func holdBegan() {}
    func holdEnded() {}
    func holdCancelled() {}
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
    /// The shared editor window (Annotate, Diff, Trim). Its exports come back through `emit`'s pipeline.
    public let editor: EditorWindowController
    private let emitHandler: @MainActor (ToolResult) -> Void
    private let activityHandler: @MainActor (String, ToolActivity) -> Void

    public init(
        overlay: OverlayController,
        editor: EditorWindowController? = nil,
        emit: @escaping @MainActor (ToolResult) -> Void,
        activity: @escaping @MainActor (String, ToolActivity) -> Void = { _, _ in }
    ) {
        self.overlay = overlay
        self.editor = editor ?? EditorWindowController()
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

/// Output of one capture. Text, a file, an in-memory image, or a mix.
public struct ToolResult: Sendable, Identifiable {
    public let id: UUID
    public let toolID: String
    public let text: String?
    public let fileURL: URL?
    /// In-memory image for `copy` (PNG + TIFF on the pasteboard) and history thumbnails. CGImage is Swift
    /// Sendable in this SDK (see CGImage.h). A tool that also wants a file on disk supplies both this and
    /// `fileURL`, e.g. a screenshot: the pasteboard gets the pixels immediately, the file is saved separately.
    public let image: CGImage?
    public let createdAt: Date
    /// Length of the captured audio or video, when known.
    public let duration: TimeInterval?
    /// History bucket. Defaults to an inference from the result's shape: an image means screenshot, a file with
    /// no image means recording, otherwise text. A tool whose kind Core cannot guess this way (meeting, convert)
    /// passes it explicitly.
    public let kind: HistoryKind
    /// A button the pill offers once the result is delivered (Annotate, Trim).
    public let followUp: ResultFollowUp?

    public init(
        toolID: String, text: String? = nil, fileURL: URL? = nil, image: CGImage? = nil,
        duration: TimeInterval? = nil, kind: HistoryKind? = nil, followUp: ResultFollowUp? = nil
    ) {
        self.followUp = followUp
        id = UUID()
        self.toolID = toolID
        self.text = text
        self.fileURL = fileURL
        self.image = image
        createdAt = Date()
        self.duration = duration
        self.kind = kind ?? (image != nil ? .screenshot : (fileURL != nil ? .recording : .text))
    }
}

/// A next step offered on the pill after a result lands, run on the delivered file (where Save put it, or the
/// staging file when Save is off).
public struct ResultFollowUp: Sendable {
    public let label: String
    public let perform: @MainActor @Sendable (URL) -> Void

    public init(label: String, perform: @escaping @MainActor @Sendable (URL) -> Void) {
        self.label = label
        self.perform = perform
    }
}
