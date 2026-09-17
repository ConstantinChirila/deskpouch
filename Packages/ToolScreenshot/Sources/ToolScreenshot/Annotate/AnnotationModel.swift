import CoreGraphics
import Foundation

/// Drawing tools the editor offers. Nothing else in v1 (01-screenshot.md): no freehand, crop, ellipse, highlighter.
public enum AnnotationTool: String, CaseIterable, Sendable {
    case arrow, box, text, blur, badge

    public var label: String {
        switch self {
        case .arrow: "Arrow"
        case .box: "Box"
        case .text: "Text"
        case .blur: "Blur"
        case .badge: "Number"
        }
    }

    /// Single-key shortcut while no text is being typed.
    public var key: Character {
        switch self {
        case .arrow: "a"
        case .box: "r"
        case .text: "t"
        case .blur: "b"
        case .badge: "n"
        }
    }
}

public enum AnnotationColor: String, CaseIterable, Sendable {
    case accent, white, ink
}

public enum StrokeSize: String, CaseIterable, Sendable {
    case thin, thick
}

/// One mark on the image. Coordinates are image pixels, top-left origin, so the canvas and the export draw the
/// same numbers.
public struct Annotation: Identifiable, Equatable, Sendable {
    public enum Shape: Equatable, Sendable {
        case arrow(from: CGPoint, to: CGPoint)
        case box(CGRect)
        /// `origin` is the top-left corner of the text plate.
        case text(origin: CGPoint, string: String)
        case blur(CGRect)
        case badge(center: CGPoint, number: Int)
    }

    public let id: UUID
    public var shape: Shape
    public var color: AnnotationColor
    public var size: StrokeSize

    public init(id: UUID = UUID(), shape: Shape, color: AnnotationColor = .accent, size: StrokeSize = .thin) {
        self.id = id
        self.shape = shape
        self.color = color
        self.size = size
    }

    /// Box and blur use corner handles, an arrow its two ends; text and badges only move.
    public enum Handle: Equatable, Sendable {
        case arrowStart, arrowEnd
        case corner(Int)
    }

    public mutating func move(by delta: CGSize) {
        switch shape {
        case .arrow(let from, let to):
            shape = .arrow(from: from.offset(delta), to: to.offset(delta))
        case .box(let rect):
            shape = .box(rect.offsetBy(dx: delta.width, dy: delta.height))
        case .text(let origin, let string):
            shape = .text(origin: origin.offset(delta), string: string)
        case .blur(let rect):
            shape = .blur(rect.offsetBy(dx: delta.width, dy: delta.height))
        case .badge(let center, let number):
            shape = .badge(center: center.offset(delta), number: number)
        }
    }

    /// Drags `handle` to `point`. A corner keeps the opposite corner fixed.
    public mutating func drag(_ handle: Handle, to point: CGPoint) {
        switch (shape, handle) {
        case (.arrow(_, let to), .arrowStart):
            shape = .arrow(from: point, to: to)
        case (.arrow(let from, _), .arrowEnd):
            shape = .arrow(from: from, to: point)
        case (.box(let rect), .corner(let index)):
            shape = .box(CGRect(corners: rect.corner(opposite: index), point))
        case (.blur(let rect), .corner(let index)):
            shape = .blur(CGRect(corners: rect.corner(opposite: index), point))
        default:
            break
        }
    }

    /// Handle positions, in the order `Handle` indexes them.
    public var handles: [(Handle, CGPoint)] {
        switch shape {
        case .arrow(let from, let to):
            [(.arrowStart, from), (.arrowEnd, to)]
        case .box(let rect), .blur(let rect):
            rect.corners.enumerated().map { (.corner($0.offset), $0.element) }
        case .text, .badge:
            []
        }
    }
}

/// Sizes that depend on the stroke setting, in image pixels. `pixelScale` is image pixels per screen point (2 for
/// a Retina capture), so a thin arrow looks the same on a 1x and a 2x screenshot.
public struct AnnotationMetrics: Sendable {
    public var pixelScale: CGFloat
    /// Width and height of a text plate for a string at a font size. The renderer measures with CoreText; tests
    /// pass a fixed rule.
    public var textSize: @Sendable (String, CGFloat) -> CGSize

    public init(pixelScale: CGFloat, textSize: @escaping @Sendable (String, CGFloat) -> CGSize) {
        self.pixelScale = pixelScale
        self.textSize = textSize
    }

    public func lineWidth(_ size: StrokeSize) -> CGFloat {
        (size == .thin ? 3 : 6) * pixelScale
    }

    public func fontSize(_ size: StrokeSize) -> CGFloat {
        (size == .thin ? 16 : 24) * pixelScale
    }

    public func badgeDiameter(_ size: StrokeSize) -> CGFloat {
        (size == .thin ? 26 : 36) * pixelScale
    }

    /// Padding inside a text plate.
    public var textInset: CGSize { CGSize(width: 7 * pixelScale, height: 4 * pixelScale) }

    /// Blur block edge. Larger than UI text is tall, so a block never holds a readable glyph shape; the renderer
    /// adds per-block noise on top (review 2026-09-17, replacing the 6 pt blocks of 01-screenshot.md).
    public var blurBlock: CGFloat { 16 * pixelScale }

    /// How far from a stroke a click still hits it.
    public var hitTolerance: CGFloat { 8 * pixelScale }

    /// Drags shorter than this create nothing.
    public var minimumDrag: CGFloat { 6 * pixelScale }

    public func textPlate(_ string: String, origin: CGPoint, size: StrokeSize) -> CGRect {
        let text = textSize(string.isEmpty ? " " : string, fontSize(size))
        return CGRect(
            x: origin.x, y: origin.y,
            width: text.width + textInset.width * 2, height: text.height + textInset.height * 2
        )
    }

    /// Area an annotation covers, for hit testing and selection outlines.
    public func bounds(of annotation: Annotation) -> CGRect {
        switch annotation.shape {
        case .arrow(let from, let to):
            return CGRect(corners: from, to).insetBy(dx: -lineWidth(annotation.size), dy: -lineWidth(annotation.size))
        case .box(let rect), .blur(let rect):
            return rect
        case .text(let origin, let string):
            return textPlate(string, origin: origin, size: annotation.size)
        case .badge(let center, _):
            let d = badgeDiameter(annotation.size)
            return CGRect(x: center.x - d / 2, y: center.y - d / 2, width: d, height: d)
        }
    }

    public func hits(_ annotation: Annotation, at point: CGPoint) -> Bool {
        let tolerance = hitTolerance
        switch annotation.shape {
        case .arrow(let from, let to):
            return point.distance(toSegment: from, to) <= tolerance + lineWidth(annotation.size) / 2
        case .box(let rect):
            // The outline only: a click inside a box should be free to start a new mark over the content.
            let outer = rect.insetBy(dx: -tolerance, dy: -tolerance)
            let inner = rect.insetBy(dx: tolerance, dy: tolerance)
            return outer.contains(point) && (inner.isNull || !inner.contains(point))
        case .blur, .text, .badge:
            return bounds(of: annotation).insetBy(dx: -tolerance / 2, dy: -tolerance / 2).contains(point)
        }
    }
}

/// The editor's document state: marks in drawing order, the selection, and undo/redo. Value type, no UI.
public struct AnnotationModel: Equatable, Sendable {
    public private(set) var annotations: [Annotation] = []
    public var selection: UUID?

    private var undoStack: [[Annotation]] = []
    private var redoStack: [[Annotation]] = []
    static let undoLimit = 200

    public init(annotations: [Annotation] = []) {
        self.annotations = annotations
    }

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    public var selected: Annotation? {
        selection.flatMap { annotation($0) }
    }

    public func annotation(_ id: UUID) -> Annotation? {
        annotations.first { $0.id == id }
    }

    /// One more than the highest badge so far, so deleting a middle badge does not renumber the next one.
    public var nextBadgeNumber: Int {
        annotations.reduce(0) { highest, annotation in
            if case .badge(_, let number) = annotation.shape { return max(highest, number) }
            return highest
        } + 1
    }

    /// Records the current marks as one undo step. Call once before a gesture that mutates through `update`.
    public mutating func checkpoint() {
        undoStack.append(annotations)
        if undoStack.count > Self.undoLimit { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    /// Drops the last checkpoint and restores what it held, without a redo step. For a gesture that turned
    /// out to be nothing (a click with the box tool).
    public mutating func revert() {
        guard let previous = undoStack.popLast() else { return }
        annotations = previous
        dropStaleSelection()
    }

    /// Adds a mark on top as one undo step and selects it.
    public mutating func add(_ annotation: Annotation) {
        checkpoint()
        annotations.append(annotation)
        selection = annotation.id
    }

    /// Changes a mark without an undo step (live drags after `checkpoint`).
    public mutating func update(_ id: UUID, _ change: (inout Annotation) -> Void) {
        guard let index = annotations.firstIndex(where: { $0.id == id }) else { return }
        change(&annotations[index])
    }

    /// Changes a mark as its own undo step. No step when nothing changed.
    public mutating func edit(_ id: UUID, _ change: (inout Annotation) -> Void) {
        guard let index = annotations.firstIndex(where: { $0.id == id }) else { return }
        var copy = annotations[index]
        change(&copy)
        guard copy != annotations[index] else { return }
        checkpoint()
        annotations[index] = copy
    }

    public mutating func delete(_ id: UUID) {
        guard annotations.contains(where: { $0.id == id }) else { return }
        checkpoint()
        annotations.removeAll { $0.id == id }
        dropStaleSelection()
    }

    public mutating func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(annotations)
        annotations = previous
        dropStaleSelection()
    }

    public mutating func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(annotations)
        annotations = next
        dropStaleSelection()
    }

    /// Topmost mark at `point`: the last drawn wins.
    public func hitTest(_ point: CGPoint, metrics: AnnotationMetrics) -> UUID? {
        annotations.last { metrics.hits($0, at: point) }?.id
    }

    /// A handle of the selected mark near `point`.
    public func handle(at point: CGPoint, metrics: AnnotationMetrics) -> Annotation.Handle? {
        guard let selected else { return nil }
        return selected.handles.first { $0.1.distance(to: point) <= metrics.hitTolerance }?.0
    }

    private mutating func dropStaleSelection() {
        if let selection, annotation(selection) == nil { self.selection = nil }
    }
}

extension CGPoint {
    func offset(_ delta: CGSize) -> CGPoint {
        CGPoint(x: x + delta.width, y: y + delta.height)
    }

    func distance(to other: CGPoint) -> CGFloat {
        hypot(x - other.x, y - other.y)
    }

    func distance(toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return distance(to: a) }
        let t = max(0, min(1, ((x - a.x) * dx + (y - a.y) * dy) / lengthSquared))
        return distance(to: CGPoint(x: a.x + t * dx, y: a.y + t * dy))
    }
}

extension CGRect {
    init(corners a: CGPoint, _ b: CGPoint) {
        self.init(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    /// Top-left, top-right, bottom-right, bottom-left.
    var corners: [CGPoint] {
        [CGPoint(x: minX, y: minY), CGPoint(x: maxX, y: minY), CGPoint(x: maxX, y: maxY), CGPoint(x: minX, y: maxY)]
    }

    func corner(opposite index: Int) -> CGPoint {
        corners[(index + 2) % 4]
    }
}
