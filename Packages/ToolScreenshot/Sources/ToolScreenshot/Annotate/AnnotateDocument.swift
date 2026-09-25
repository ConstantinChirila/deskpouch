import AppKit
import DeskpouchCapture
import DeskpouchCore
import Observation
import SwiftUI

/// The Annotate editor for one screenshot file: tools, colours, stroke, undo, and the pointer logic the canvas
/// feeds in image pixels. Export writes `… annotated.png` beside the source and never touches the original.
@MainActor
@Observable
public final class AnnotateDocument: EditorDocument {
    /// Text being typed. `id` is set when an existing text mark is being edited (it is hidden meanwhile).
    struct TextDraft: Equatable {
        var id: UUID?
        var origin: CGPoint
        var string: String
        var color: AnnotationColor
        var size: StrokeSize
    }

    private enum Gesture {
        case create(UUID, start: CGPoint)
        case move(UUID, last: CGPoint, before: Annotation)
        /// A badge just placed: its `add` is the undo step, dragging only positions it.
        case place(UUID, last: CGPoint)
        case handle(UUID, Annotation.Handle, before: Annotation)
    }

    public let sourceURL: URL
    let toolID: String
    let renderer: AnnotationRenderer
    let pixelScale: CGFloat

    var model = AnnotationModel()
    var tool: AnnotationTool = .arrow
    var color: AnnotationColor = .accent
    var size: StrokeSize = .thin
    var draft: TextDraft?

    @ObservationIgnored private var gesture: Gesture?

    /// `renderer` is built off the main actor by the caller (it pixelates the whole image).
    public init(sourceURL: URL, renderer: AnnotationRenderer, toolID: String) {
        self.sourceURL = sourceURL
        self.toolID = toolID
        self.renderer = renderer
        pixelScale = renderer.metrics.pixelScale
    }

    /// Builds the renderer in place. Small images and tests only.
    convenience init(sourceURL: URL, image: CGImage, pixelScale: CGFloat, toolID: String) {
        let renderer = AnnotationRenderer(base: image, pixelScale: max(1, pixelScale), fontName: AnnotationRenderer.textFontName)
        self.init(sourceURL: sourceURL, renderer: renderer, toolID: toolID)
    }

    var metrics: AnnotationMetrics { renderer.metrics }

    /// Marks to draw: the one being retyped is left out, the draft stands in for it.
    var visibleAnnotations: [Annotation] {
        guard let hidden = draft?.id else { return model.annotations }
        return model.annotations.filter { $0.id != hidden }
    }

    // MARK: EditorDocument

    public var title: String { "Annotate" }

    /// One window per file: annotating an open file again brings its window forward.
    public var documentKey: String? { "annotate:" + sourceURL.standardizedFileURL.path }

    /// File name and what is on disk, so it is clear the capture is kept whatever happens to the marks.
    public var subtitle: String {
        let state = hasUnsavedMarks ? "marks not exported" : "original saved"
        return "\(sourceURL.lastPathComponent) · \(state)"
    }

    public var unsavedChanges: UnsavedChanges? {
        guard hasUnsavedMarks else { return nil }
        return UnsavedChanges(
            title: "Discard your annotations?",
            detail: "The screenshot itself is already saved \(originalLocation). Your marks are not; Export saves them as a copy next to it."
        )
    }

    /// Marks on the canvas, or text being typed.
    var hasUnsavedMarks: Bool {
        !model.annotations.isEmpty || !(draft?.string.trimmingCharacters(in: .whitespaces).isEmpty ?? true)
    }

    /// "in ~/Pictures/Deskpouch", or history when Save was off and the file stayed in Application Support.
    var originalLocation: String {
        let folder = sourceURL.deletingLastPathComponent().path
        if folder.contains("/Library/Application Support/") { return "in Deskpouch's history" }
        return "in " + (folder as NSString).abbreviatingWithTildeInPath
    }

    public var idealContentSize: CGSize {
        CGSize(
            width: renderer.imageSize.width / pixelScale + AnnotationCanvas.inset * 2,
            height: renderer.imageSize.height / pixelScale + AnnotationCanvas.inset * 2
        )
    }

    public func makeContent() -> AnyView {
        AnyView(AnnotationCanvas(document: self))
    }

    public func makeToolbar() -> AnyView {
        AnyView(AnnotateToolbar(document: self))
    }

    /// Renders off the main actor, then copies.
    public func copy() {
        commitDraft()
        let renderer = renderer
        let annotations = model.annotations
        Task {
            let image = await Task.detached(priority: .userInitiated) { renderer.render(annotations) }.value
            guard let image else { return }
            SystemOutputEffects().copyImage(image, pngData: nil)
        }
    }

    public func export() async throws -> ToolResult? {
        commitDraft()
        let renderer = renderer
        let annotations = model.annotations
        let destination = CaptureNaming.unique(Self.exportURL(for: sourceURL))
        let scale = pixelScale
        // Render and encode together off the main actor: both are full-size work.
        let image = try await Task.detached(priority: .userInitiated) { () throws -> CGImage in
            guard let image = renderer.render(annotations) else { throw AnnotateError.renderFailed }
            try ImageWriter.write(image, to: destination, format: .png, pixelsPerPoint: scale)
            return image
        }.value
        return ToolResult(toolID: toolID, fileURL: destination, image: image, kind: .screenshot)
    }

    public func handleKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        if flags == .command, key == "z" {
            undo()
            return true
        }
        if flags == [.command, .shift], key == "z" {
            redo()
            return true
        }
        guard flags.isSubset(of: .shift) else { return false }
        switch event.keyCode {
        case 51, 117: // delete, forward delete
            guard let id = model.selection else { return false }
            model.delete(id)
            return true
        case 123, 124, 125, 126: // arrows nudge the selection
            guard let id = model.selection else { return false }
            let step = (flags.contains(.shift) ? 10 : 1) * pixelScale
            let delta: CGSize = switch event.keyCode {
            case 123: CGSize(width: -step, height: 0)
            case 124: CGSize(width: step, height: 0)
            case 125: CGSize(width: 0, height: step)
            default: CGSize(width: 0, height: -step)
            }
            model.edit(id) { $0.move(by: delta) }
            return true
        default:
            break
        }
        guard flags.isEmpty, key.count == 1, let tool = AnnotationTool.allCases.first(where: { String($0.key) == key }) else {
            return false
        }
        select(tool)
        return true
    }

    public func cancel() -> Bool {
        if draft != nil {
            commitDraft()
            return true
        }
        if model.selection != nil {
            model.selection = nil
            return true
        }
        return false
    }

    public func close() {
        draft = nil
        gesture = nil
    }

    // MARK: Toolbar

    func select(_ tool: AnnotationTool) {
        commitDraft()
        self.tool = tool
        model.selection = nil
    }

    func setColor(_ color: AnnotationColor) {
        self.color = color
        draft?.color = color
        if let id = model.selection { model.edit(id) { $0.color = color } }
    }

    func setSize(_ size: StrokeSize) {
        self.size = size
        draft?.size = size
        if let id = model.selection { model.edit(id) { $0.size = size } }
    }

    /// Not during a drag: `pointerUp` takes the top of the undo stack to be the gesture's own checkpoint.
    func undo() {
        guard gesture == nil else { return }
        commitDraft()
        model.undo()
    }

    func redo() {
        guard gesture == nil else { return }
        commitDraft()
        model.redo()
    }

    // MARK: Pointer (image pixels)

    func pointerDown(at point: CGPoint, clickCount: Int) {
        commitDraft()
        if let handle = model.handle(at: point, metrics: metrics), let selected = model.selected {
            model.checkpoint()
            gesture = .handle(selected.id, handle, before: selected)
            return
        }
        if let id = model.hitTest(point, metrics: metrics), let hit = model.annotation(id) {
            if clickCount >= 2, case .text(let origin, let string) = hit.shape {
                model.selection = nil
                draft = TextDraft(id: id, origin: origin, string: string, color: hit.color, size: hit.size)
                gesture = nil
                return
            }
            model.selection = id
            if hit.color != color || hit.size != size {
                color = hit.color
                size = hit.size
            }
            model.checkpoint()
            gesture = .move(id, last: point, before: hit)
            return
        }
        model.selection = nil
        switch tool {
        case .text:
            let plate = metrics.textPlate("", origin: .zero, size: size)
            draft = TextDraft(
                id: nil, origin: CGPoint(x: point.x, y: point.y - plate.height / 2), string: "", color: color, size: size
            )
            gesture = nil
        case .badge:
            let badge = Annotation(shape: .badge(center: point, number: model.nextBadgeNumber), color: color, size: size)
            model.add(badge)
            gesture = .place(badge.id, last: point)
        case .arrow, .box, .blur:
            let shape: Annotation.Shape = switch tool {
            case .arrow: .arrow(from: point, to: point)
            case .box: .box(CGRect(origin: point, size: .zero))
            default: .blur(CGRect(origin: point, size: .zero))
            }
            let mark = Annotation(shape: shape, color: color, size: size)
            model.add(mark)
            gesture = .create(mark.id, start: point)
        }
    }

    /// `constrained` (Shift): arrows snap to 45°, boxes and blurs become squares.
    func pointerDragged(to point: CGPoint, constrained: Bool) {
        switch gesture {
        case .create(let id, let start):
            let end = constrained ? Self.constrain(point, from: start, tool: tool) : point
            model.update(id) { mark in
                switch mark.shape {
                case .arrow: mark.shape = .arrow(from: start, to: end)
                case .box: mark.shape = .box(CGRect(corners: start, end))
                case .blur: mark.shape = .blur(CGRect(corners: start, end))
                default: break
                }
            }
        case .move(let id, let last, let before):
            model.update(id) { $0.move(by: CGSize(width: point.x - last.x, height: point.y - last.y)) }
            gesture = .move(id, last: point, before: before)
        case .place(let id, let last):
            model.update(id) { $0.move(by: CGSize(width: point.x - last.x, height: point.y - last.y)) }
            gesture = .place(id, last: point)
        case .handle(let id, let handle, _):
            model.update(id) { $0.drag(handle, to: point) }
        case nil:
            break
        }
    }

    func pointerUp(at point: CGPoint) {
        defer { gesture = nil }
        switch gesture {
        case .create(let id, let start):
            // A click, not a drag: nothing to keep.
            let end = model.annotation(id).map { mark -> CGFloat in
                switch mark.shape {
                case .arrow(let from, let to): from.distance(to: to)
                case .box(let rect), .blur(let rect): min(rect.width, rect.height)
                default: start.distance(to: point)
                }
            } ?? 0
            if end < metrics.minimumDrag { model.revert() }
        case .move(let id, _, let before), .handle(let id, _, let before):
            // A click that changed nothing leaves no undo step.
            if model.annotation(id) == before { model.revert() }
        case .place, nil:
            break
        }
    }

    // MARK: Text

    func commitDraft() {
        guard let draft else { return }
        self.draft = nil
        let string = draft.string.trimmingCharacters(in: .whitespacesAndNewlines)
        if let id = draft.id {
            if string.isEmpty {
                model.delete(id)
            } else {
                model.edit(id) {
                    $0.shape = .text(origin: draft.origin, string: string)
                    $0.color = draft.color
                    $0.size = draft.size
                }
            }
        } else if !string.isEmpty {
            model.add(Annotation(shape: .text(origin: draft.origin, string: string), color: draft.color, size: draft.size))
        }
    }

    // MARK: Helpers

    static func constrain(_ point: CGPoint, from start: CGPoint, tool: AnnotationTool) -> CGPoint {
        let dx = point.x - start.x
        let dy = point.y - start.y
        if tool == .arrow {
            let angle = (atan2(dy, dx) / (.pi / 4)).rounded() * (.pi / 4)
            let length = hypot(dx, dy)
            return CGPoint(x: start.x + cos(angle) * length, y: start.y + sin(angle) * length)
        }
        let side = max(abs(dx), abs(dy))
        return CGPoint(x: start.x + (dx < 0 ? -side : side), y: start.y + (dy < 0 ? -side : side))
    }

    /// `Screenshot 2026-09-16 14.05.02.png` -> `… annotated.png` in the same folder. Re-annotating an annotated
    /// file does not stack the suffix; `CaptureNaming.unique` numbers it instead.
    static func exportURL(for source: URL) -> URL {
        var base = source.deletingPathExtension().lastPathComponent
        if let range = base.range(of: #" annotated( \d+)?$"#, options: .regularExpression) {
            base.removeSubrange(range)
        }
        return source.deletingLastPathComponent().appending(path: "\(base) annotated.png")
    }
}

enum AnnotateError: Error {
    case renderFailed
    case unreadable(URL)
}
