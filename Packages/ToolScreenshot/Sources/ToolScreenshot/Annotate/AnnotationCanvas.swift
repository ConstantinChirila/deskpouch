import AppKit
import DeskpouchCore
import SwiftUI

/// The image on a dark well, marks drawn over it by `AnnotationRenderer`, selection handles, and the text field
/// while typing. Fits the image into the area, never past 1:1 points.
struct AnnotationCanvas: View {
    let document: AnnotateDocument
    /// A press is in progress. Tracked here rather than read off a zero translation, which also happens when a
    /// drag returns to its start point.
    @State private var pressed = false

    /// Well padding around the image.
    static let inset: CGFloat = 12

    var body: some View {
        GeometryReader { geometry in
            let layout = Layout(document: document, area: geometry.size)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .fill(Theme.Colors.well)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                            .strokeBorder(Theme.Colors.tint(0.08), lineWidth: 1)
                    )
                TransparencyChecker()
                    .frame(width: layout.frame.width, height: layout.frame.height)
                    .offset(x: layout.frame.minX, y: layout.frame.minY)
                Image(decorative: document.renderer.base, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: layout.frame.width, height: layout.frame.height)
                    .offset(x: layout.frame.minX, y: layout.frame.minY)
                    .shadow(color: .black.opacity(0.45), radius: 14, y: 6)
                marks(layout)
                selection(layout)
                if let draft = document.draft {
                    TextDraftField(document: document, draft: draft, layout: layout)
                }
            }
            .contentShape(Rectangle())
            .gesture(drag(layout))
            .pointerStyle(document.draft == nil ? .rectSelection : nil)
        }
        .accessibilityElement()
        .accessibilityLabel("Screenshot with \(document.model.annotations.count) annotations")
    }

    private func marks(_ layout: Layout) -> some View {
        // Read here so the canvas redraws when the marks change.
        let annotations = document.visibleAnnotations
        let renderer = document.renderer
        return Canvas { context, _ in
            context.withCGContext { cg in
                cg.scaleBy(x: layout.scale, y: layout.scale)
                renderer.draw(annotations, in: cg)
            }
        }
        .frame(width: layout.frame.width, height: layout.frame.height)
        .clipped()
        .offset(x: layout.frame.minX, y: layout.frame.minY)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func selection(_ layout: Layout) -> some View {
        if let selected = document.model.selected {
            let bounds = layout.view(document.metrics.bounds(of: selected)).insetBy(dx: -4, dy: -4)
            ZStack(alignment: .topLeading) {
                if selected.handles.isEmpty || isRect(selected) {
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Theme.Colors.text.opacity(0.9), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .frame(width: bounds.width, height: bounds.height)
                        .offset(x: bounds.minX, y: bounds.minY)
                }
                ForEach(Array(selected.handles.enumerated()), id: \.offset) { _, handle in
                    let point = layout.view(handle.1)
                    Circle()
                        .fill(Theme.Colors.text)
                        .overlay(Circle().strokeBorder(Theme.Colors.accent, lineWidth: 2))
                        .frame(width: 10, height: 10)
                        .shadow(color: .black.opacity(0.4), radius: 2)
                        .offset(x: point.x - 5, y: point.y - 5)
                }
            }
            .allowsHitTesting(false)
        }
    }

    private func isRect(_ annotation: Annotation) -> Bool {
        if case .arrow = annotation.shape { return false }
        return true
    }

    private func drag(_ layout: Layout) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                if !pressed {
                    pressed = true
                    document.pointerDown(at: layout.image(value.startLocation), clickCount: NSApp.currentEvent?.clickCount ?? 1)
                }
                document.pointerDragged(to: layout.image(value.location), constrained: NSEvent.modifierFlags.contains(.shift))
            }
            .onEnded { value in
                pressed = false
                document.pointerUp(at: layout.image(value.location))
            }
    }

    /// Where the image sits in the canvas and how view points map to image pixels.
    struct Layout {
        /// Image rect in view points.
        let frame: CGRect
        /// View points per image pixel.
        let scale: CGFloat

        @MainActor
        init(document: AnnotateDocument, area: CGSize) {
            let pixels = document.renderer.imageSize
            let available = CGSize(width: max(1, area.width - AnnotationCanvas.inset * 2), height: max(1, area.height - AnnotationCanvas.inset * 2))
            let scale = min(1 / document.pixelScale, available.width / pixels.width, available.height / pixels.height)
            let size = CGSize(width: (pixels.width * scale).rounded(), height: (pixels.height * scale).rounded())
            frame = CGRect(x: ((area.width - size.width) / 2).rounded(), y: ((area.height - size.height) / 2).rounded(), width: size.width, height: size.height)
            self.scale = scale
        }

        func image(_ point: CGPoint) -> CGPoint {
            CGPoint(x: (point.x - frame.minX) / scale, y: (point.y - frame.minY) / scale)
        }

        func view(_ point: CGPoint) -> CGPoint {
            CGPoint(x: frame.minX + point.x * scale, y: frame.minY + point.y * scale)
        }

        func view(_ rect: CGRect) -> CGRect {
            let origin = view(rect.origin)
            return CGRect(x: origin.x, y: origin.y, width: rect.width * scale, height: rect.height * scale)
        }
    }
}

/// The text being typed, styled like the plate it becomes.
private struct TextDraftField: View {
    let document: AnnotateDocument
    let draft: AnnotateDocument.TextDraft
    let layout: AnnotationCanvas.Layout
    @FocusState private var focused: Bool

    var body: some View {
        let metrics = document.metrics
        let fontSize = metrics.fontSize(draft.size) * layout.scale
        let inset = CGSize(width: metrics.textInset.width * layout.scale, height: metrics.textInset.height * layout.scale)
        let plate = layout.view(metrics.textPlate(draft.string + "M", origin: draft.origin, size: draft.size))
        TextField("", text: Binding(
            get: { document.draft?.string ?? "" },
            set: { document.draft?.string = $0 }
        ))
        .textFieldStyle(.plain)
        .font(.dp(fontSize, .semibold))
        .foregroundStyle(Color(cgColor: AnnotationRenderer.ink(on: draft.color)))
        .focused($focused)
        .onSubmit { document.commitDraft() }
        .onExitCommand { document.commitDraft() }
        .padding(.horizontal, inset.width)
        .padding(.vertical, inset.height)
        .frame(width: max(plate.width, 40), height: plate.height, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 5 * document.pixelScale * layout.scale, style: .continuous)
                .fill(Color(cgColor: AnnotationRenderer.fill(draft.color)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 5 * document.pixelScale * layout.scale, style: .continuous)
                .strokeBorder(Theme.Colors.accent, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .padding(-3)
        )
        .offset(x: plate.minX, y: plate.minY)
        .task(id: draft.id) { focused = true }
        .onAppear { focused = true }
    }
}

/// Soft checkerboard behind the image so transparent window shadows read as transparent.
private struct TransparencyChecker: View {
    var body: some View {
        Canvas { context, size in
            let cell: CGFloat = 8
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.16)))
            var y: CGFloat = 0
            var row = 0
            while y < size.height {
                var x: CGFloat = row.isMultiple(of: 2) ? 0 : cell
                while x < size.width {
                    context.fill(Path(CGRect(x: x, y: y, width: cell, height: cell)), with: .color(Color(white: 0.21)))
                    x += cell * 2
                }
                y += cell
                row += 1
            }
        }
    }
}
