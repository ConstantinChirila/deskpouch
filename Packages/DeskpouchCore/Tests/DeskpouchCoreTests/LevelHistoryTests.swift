import Foundation
import Testing
@testable import DeskpouchCore

struct LevelHistoryTests {
    @Test func startsSilent() {
        let h = LevelHistory(count: 5)
        #expect(h.bars == [0, 0, 0, 0, 0])
        #expect(h.current == 0)
    }

    @Test func newSampleEntersOnTheRight() {
        var h = LevelHistory(count: 3)
        h.push(level: 1, dt: 1 / 30)
        #expect(h.bars == [0, 0, 1])
        h.push(level: 0.5, dt: 1)
        #expect(h.bars.count == 3)
        #expect(h.bars[1] == 1)
        #expect(h.bars[2] == 0.5)
    }

    @Test func decaysWithTimeConstant() {
        var h = LevelHistory(count: 2, decay: 0.08)
        h.push(level: 1, dt: 1 / 30)
        h.push(level: 0, dt: 0.08)
        #expect(abs(h.current - Float(exp(-1.0))) < 0.001)
    }

    @Test func louderSampleOverridesDecay() {
        var h = LevelHistory(count: 2)
        h.push(level: 0.2, dt: 1 / 30)
        h.push(level: 0.9, dt: 1 / 30)
        #expect(h.current == 0.9)
    }

    @Test func clampsInput() {
        var h = LevelHistory(count: 1)
        h.push(level: 4, dt: 1 / 30)
        #expect(h.current == 1)
        h.push(level: -3, dt: 10)
        #expect(h.current >= 0)
    }

    @Test func resetClears() {
        var h = LevelHistory(count: 2)
        h.push(level: 1, dt: 1 / 30)
        h.reset()
        #expect(h.bars == [0, 0])
        #expect(h.current == 0)
    }
}
