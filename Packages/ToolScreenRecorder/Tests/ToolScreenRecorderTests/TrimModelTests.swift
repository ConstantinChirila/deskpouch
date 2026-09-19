import Foundation
import Testing
@testable import ToolScreenRecorder

struct TrimModelTests {
    @Test func startsWithEverythingKept() {
        let model = TrimModel(duration: 10, frameRate: 60)
        #expect(model.start == 0)
        #expect(model.end == 10)
        #expect(!model.isTrimmed)
    }

    @Test func handlesSnapToTenths() {
        var model = TrimModel(duration: 10, frameRate: 60)
        model.setStart(1.234)
        model.setEnd(8.77)
        #expect(abs(model.start - 1.2) < 1e-9)
        #expect(abs(model.end - 8.8) < 1e-9)
        #expect(model.isTrimmed)
    }

    @Test func theVeryEndStaysReachable() {
        var model = TrimModel(duration: 4.03, frameRate: 60)
        model.setEnd(2)
        model.setEnd(4.02)
        #expect(model.end == 4.03)
    }

    @Test func aHandleDraggedPastTheOtherStopsShortOfIt() {
        var model = TrimModel(duration: 10, frameRate: 60)
        model.setEnd(6)
        model.setStart(9)
        #expect(model.start == 5.5)
        #expect(model.end == 6)
        model.setEnd(1)
        #expect(model.start == 5.5)
        #expect(model.end == 6)
    }

    @Test func aRecordingShorterThanTheMinimumIsKeptWhole() {
        var model = TrimModel(duration: 0.3, frameRate: 60)
        model.setStart(0.2)
        model.setEnd(0.1)
        #expect(model.start == 0)
        #expect(model.end == 0.3)
    }

    @Test func arrowsStepWholeFramesInsideTheRecording() {
        var model = TrimModel(duration: 1, frameRate: 60)
        model.step(frames: 1)
        #expect(abs(model.playhead - 1.0 / 60) < 1e-9)
        model.step(frames: -5)
        #expect(model.playhead == 0)
        model.seek(to: 1)
        model.step(frames: 3)
        #expect(model.playhead == 1)
    }

    @Test func marksTakeThePlayheadUnsnapped() {
        var model = TrimModel(duration: 10, frameRate: 60)
        model.seek(to: 2.345)
        model.markIn()
        model.seek(to: 7.891)
        model.markOut()
        #expect(model.start == 2.345)
        #expect(model.end == 7.891)
        #expect(abs(model.selectedDuration - 5.546) < 1e-9)
    }

    @Test func movingAHandleKeepsThePlayheadInside() {
        var model = TrimModel(duration: 10, frameRate: 60)
        model.seek(to: 1)
        model.setStart(3)
        #expect(model.playhead == 3)
        model.seek(to: 9)
        model.setEnd(6)
        #expect(model.playhead == 6)
    }

    @Test func unusableFrameRateFallsBackToSixty() {
        #expect(TrimModel(duration: 1, frameRate: 0).frameRate == 60)
        #expect(TrimModel(duration: 1, frameRate: .nan).frameRate == 60)
    }

    @Test func labels() {
        #expect(TrimModel.label(4.23) == "0:04.2")
        #expect(TrimModel.label(75.96) == "1:16.0")
    }
}
