import Foundation
import Testing
@testable import DeskpouchGallery

struct GallerySelectionTests {
    static let order = (0..<6).map { _ in UUID() }
    var order: [UUID] { Self.order }

    @Test func aPlainClickReplaces() {
        var selection = GallerySelection()
        selection.click(order[1], in: order, command: false, shift: false)
        selection.click(order[3], in: order, command: false, shift: false)
        #expect(selection.ids == [order[3]])
        #expect(selection.focus == order[3])
    }

    @Test func shiftSelectsFromTheAnchorInEitherDirection() {
        var selection = GallerySelection()
        selection.click(order[3], in: order, command: false, shift: false)
        selection.click(order[5], in: order, command: false, shift: true)
        #expect(selection.ids == Set(order[3...5]))
        // A second Shift click pivots on the same anchor instead of growing from the last row.
        selection.click(order[1], in: order, command: false, shift: true)
        #expect(selection.ids == Set(order[1...3]))
        #expect(selection.focus == order[1])
        #expect(selection.anchor == order[3])
    }

    @Test func commandTogglesAndMovesThePreviewOffARemovedRow() {
        var selection = GallerySelection()
        selection.click(order[1], in: order, command: false, shift: false)
        selection.click(order[4], in: order, command: true, shift: false)
        #expect(selection.ids == [order[1], order[4]])
        #expect(selection.focus == order[4])
        selection.click(order[4], in: order, command: true, shift: false)
        #expect(selection.ids == [order[1]])
        #expect(selection.focus == order[1])
        selection.click(order[1], in: order, command: true, shift: false)
        #expect(selection.isEmpty)
        #expect(selection.focus == nil)
    }

    @Test func arrowsMoveClampAndExtend() {
        var selection = GallerySelection()
        selection.move(by: 1, in: order, extending: false)
        #expect(selection.ids == [order[0]])
        selection.move(by: -1, in: order, extending: false)
        #expect(selection.ids == [order[0]])
        selection.move(by: 2, in: order, extending: true)
        #expect(selection.ids == Set(order[0...2]))
        selection.move(by: -1, in: order, extending: true)
        #expect(selection.ids == Set(order[0...1]))
        selection.move(by: 99, in: order, extending: false)
        #expect(selection.ids == [order[5]])
        var fromNothing = GallerySelection()
        fromNothing.move(by: -1, in: order, extending: false)
        #expect(fromNothing.ids == [order[5]])
    }

    @Test func selectAllKeepsThePreviewWhereItWas() {
        var selection = GallerySelection()
        selection.set(order[2])
        selection.selectAll(in: order)
        #expect(selection.ids == Set(order))
        #expect(selection.focus == order[2])
    }

    @Test func pruneDropsRowsThatLeftTheList() {
        var selection = GallerySelection()
        selection.click(order[1], in: order, command: false, shift: false)
        selection.click(order[3], in: order, command: false, shift: true)
        selection.prune(to: [order[0], order[1], order[2]])
        #expect(selection.ids == [order[1], order[2]])
        #expect(selection.focus == order[1])
        selection.prune(to: [])
        #expect(selection.isEmpty)
        #expect(selection.focus == nil)
    }

    @Test func afterADeleteTheNextRowDownElseTheOneAbove() {
        var selection = GallerySelection()
        selection.set(order[2])
        #expect(selection.successor(in: order) == order[3])
        selection.click(order[4], in: order, command: true, shift: false)
        #expect(selection.successor(in: order) == order[5])
        selection.set(order[5])
        #expect(selection.successor(in: order) == order[4])
        selection.selectAll(in: order)
        #expect(selection.successor(in: order) == nil)
    }
}
