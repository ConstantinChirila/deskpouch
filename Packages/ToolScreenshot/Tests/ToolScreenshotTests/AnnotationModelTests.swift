import CoreGraphics
import Foundation
import Testing
@testable import ToolScreenshot

struct AnnotationModelTests {
    /// 1x metrics with a fixed text rule: 10 px per character, one font size tall.
    let metrics = AnnotationMetrics(pixelScale: 1) { string, size in
        CGSize(width: CGFloat(string.count) * 10, height: size)
    }

    func box(_ rect: CGRect) -> Annotation {
        Annotation(shape: .box(rect))
    }

    @Test func addSelectsAndUndoRedoRestore() {
        var model = AnnotationModel()
        let first = box(CGRect(x: 0, y: 0, width: 50, height: 50))
        let second = Annotation(shape: .arrow(from: .zero, to: CGPoint(x: 100, y: 0)))
        model.add(first)
        model.add(second)
        #expect(model.annotations.map(\.id) == [first.id, second.id])
        #expect(model.selection == second.id)

        model.undo()
        #expect(model.annotations.map(\.id) == [first.id])
        #expect(model.selection == nil)
        #expect(model.canRedo)

        model.redo()
        #expect(model.annotations.map(\.id) == [first.id, second.id])
        #expect(!model.canRedo)
    }

    @Test func newEditClearsRedo() {
        var model = AnnotationModel()
        model.add(box(CGRect(x: 0, y: 0, width: 10, height: 10)))
        model.undo()
        model.add(box(CGRect(x: 5, y: 5, width: 10, height: 10)))
        #expect(!model.canRedo)
    }

    @Test func liveMoveIsOneUndoStep() {
        var model = AnnotationModel()
        let mark = box(CGRect(x: 0, y: 0, width: 10, height: 10))
        model.add(mark)
        model.checkpoint()
        for _ in 0..<5 {
            model.update(mark.id) { $0.move(by: CGSize(width: 4, height: 2)) }
        }
        #expect(model.annotation(mark.id)?.shape == .box(CGRect(x: 20, y: 10, width: 10, height: 10)))
        model.undo()
        #expect(model.annotation(mark.id)?.shape == .box(CGRect(x: 0, y: 0, width: 10, height: 10)))
    }

    @Test func revertDropsTheCheckpointWithoutRedo() {
        var model = AnnotationModel()
        model.checkpoint()
        model.update(UUID()) { _ in }
        model.revert()
        #expect(!model.canUndo)
        #expect(!model.canRedo)
    }

    @Test func editWithNoChangeAddsNoStep() {
        var model = AnnotationModel()
        let mark = box(CGRect(x: 0, y: 0, width: 10, height: 10))
        model.add(mark)
        model.undo()
        model.redo()
        model.edit(mark.id) { $0.color = .accent }
        model.undo()
        #expect(model.annotations.isEmpty)
        model.redo()
        model.edit(mark.id) { $0.color = .ink }
        #expect(model.annotation(mark.id)?.color == .ink)
        model.undo()
        #expect(model.annotation(mark.id)?.color == .accent)
    }

    @Test func deleteIsUndoable() {
        var model = AnnotationModel()
        let mark = box(CGRect(x: 0, y: 0, width: 10, height: 10))
        model.add(mark)
        model.delete(mark.id)
        #expect(model.annotations.isEmpty)
        #expect(model.selection == nil)
        model.undo()
        #expect(model.annotations.count == 1)
    }

    @Test func hitTestPicksTheLastDrawn() {
        var model = AnnotationModel()
        let under = Annotation(shape: .blur(CGRect(x: 0, y: 0, width: 100, height: 100)))
        let over = Annotation(shape: .blur(CGRect(x: 50, y: 50, width: 100, height: 100)))
        model.add(under)
        model.add(over)
        #expect(model.hitTest(CGPoint(x: 75, y: 75), metrics: metrics) == over.id)
        #expect(model.hitTest(CGPoint(x: 20, y: 20), metrics: metrics) == under.id)
        #expect(model.hitTest(CGPoint(x: 300, y: 300), metrics: metrics) == nil)
    }

    @Test func boxHitsOnItsOutlineOnly() {
        var model = AnnotationModel()
        model.add(box(CGRect(x: 0, y: 0, width: 100, height: 100)))
        #expect(model.hitTest(CGPoint(x: 2, y: 50), metrics: metrics) != nil)
        #expect(model.hitTest(CGPoint(x: 50, y: 50), metrics: metrics) == nil)
    }

    @Test func arrowHitsNearItsLine() {
        var model = AnnotationModel()
        model.add(Annotation(shape: .arrow(from: .zero, to: CGPoint(x: 100, y: 100))))
        #expect(model.hitTest(CGPoint(x: 52, y: 48), metrics: metrics) != nil)
        #expect(model.hitTest(CGPoint(x: 80, y: 20), metrics: metrics) == nil)
    }

    @Test func textHitsItsPlate() {
        var model = AnnotationModel()
        model.add(Annotation(shape: .text(origin: CGPoint(x: 10, y: 10), string: "Hello")))
        // Plate: 5 chars * 10 + 2 * 7 wide, 16 + 2 * 4 tall.
        #expect(metrics.bounds(of: model.annotations[0]) == CGRect(x: 10, y: 10, width: 64, height: 24))
        #expect(model.hitTest(CGPoint(x: 70, y: 30), metrics: metrics) != nil)
        #expect(model.hitTest(CGPoint(x: 90, y: 30), metrics: metrics) == nil)
    }

    @Test func badgeNumbersKeepCounting() {
        var model = AnnotationModel()
        #expect(model.nextBadgeNumber == 1)
        let one = Annotation(shape: .badge(center: .zero, number: 1))
        model.add(one)
        model.add(Annotation(shape: .badge(center: .zero, number: 2)))
        model.delete(one.id)
        #expect(model.nextBadgeNumber == 3)
    }

    @Test func cornerDragKeepsTheOppositeCorner() {
        var mark = box(CGRect(x: 10, y: 10, width: 50, height: 50))
        // Corner 2 is bottom-right; drag it past the top-left anchor.
        mark.drag(.corner(2), to: CGPoint(x: 0, y: 0))
        #expect(mark.shape == .box(CGRect(x: 0, y: 0, width: 10, height: 10)))
    }

    @Test func handleLookupUsesTheSelection() {
        var model = AnnotationModel()
        let arrow = Annotation(shape: .arrow(from: .zero, to: CGPoint(x: 100, y: 0)))
        model.add(arrow)
        #expect(model.handle(at: CGPoint(x: 98, y: 3), metrics: metrics) == .arrowEnd)
        model.selection = nil
        #expect(model.handle(at: CGPoint(x: 98, y: 3), metrics: metrics) == nil)
    }
}
