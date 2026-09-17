import CoreGraphics
import Testing
@testable import DeskpouchCapture

@MainActor
struct PickerModelTests {
    // Primary 1000x800 at origin, a second screen to its right. CG y is flipped from AppKit y.
    static let primary = PickerScreen(id: 0, displayID: 1, frame: CGRect(x: 0, y: 0, width: 1000, height: 800),
                                      cgFrame: CGRect(x: 0, y: 0, width: 1000, height: 800), backingScale: 2)
    static let second = PickerScreen(id: 1, displayID: 2, frame: CGRect(x: 1000, y: 100, width: 800, height: 600),
                                     cgFrame: CGRect(x: 1000, y: 100, width: 800, height: 600), backingScale: 1)
    static let front = PickerWindow(id: 10, frame: CGRect(x: 100, y: 100, width: 300, height: 200), title: "Front", appName: "A")
    static let back = PickerWindow(id: 11, frame: CGRect(x: 50, y: 50, width: 600, height: 500), title: "Back", appName: "B")

    func model(mode: PickerMode = .region) -> PickerModel {
        PickerModel(mode: mode, screens: [Self.primary, Self.second], windows: [Self.front, Self.back],
                    toolbarScreenID: 0, systemAudio: true, microphone: false, frameRate: 60)
    }

    @Test func dragDrawsARegionAndReturnConfirmsIt() {
        let m = model()
        var finished: PickerSelection??
        m.onFinish = { finished = .some($0) }
        m.dragChanged(screenID: 0, location: CGPoint(x: 200, y: 300))
        m.dragChanged(screenID: 0, location: CGPoint(x: 120, y: 340))
        m.dragEnded(screenID: 0, location: CGPoint(x: 120, y: 340))
        #expect(m.regionRect(on: 0) == CGRect(x: 120, y: 300, width: 80, height: 40))
        #expect(m.dimensionLabel == "80 × 40")
        #expect(m.canRecord)
        m.confirm()
        #expect(finished == .some(.region(screen: Self.primary, rect: CGRect(x: 120, y: 300, width: 80, height: 40))))
    }

    @Test func tinyDragClearsTheRegion() {
        let m = model()
        m.dragChanged(screenID: 0, location: CGPoint(x: 200, y: 300))
        m.dragChanged(screenID: 0, location: CGPoint(x: 203, y: 302))
        m.dragEnded(screenID: 0, location: CGPoint(x: 203, y: 302))
        #expect(m.regionRect(on: 0) == nil)
        #expect(!m.canRecord)
    }

    @Test func draggingInsideTheRegionMovesIt() {
        let m = model()
        m.dragChanged(screenID: 0, location: CGPoint(x: 100, y: 100))
        m.dragChanged(screenID: 0, location: CGPoint(x: 300, y: 200))
        m.dragEnded(screenID: 0, location: CGPoint(x: 300, y: 200))
        m.dragChanged(screenID: 0, location: CGPoint(x: 150, y: 150))
        m.dragChanged(screenID: 0, location: CGPoint(x: 170, y: 180))
        m.dragEnded(screenID: 0, location: CGPoint(x: 170, y: 180))
        #expect(m.regionRect(on: 0) == CGRect(x: 120, y: 130, width: 200, height: 100))
    }

    @Test func doubleClickInsideTheRegionConfirmsIt() {
        let m = model()
        var finished: PickerSelection??
        m.onFinish = { finished = .some($0) }
        m.dragChanged(screenID: 0, location: CGPoint(x: 100, y: 100))
        m.dragChanged(screenID: 0, location: CGPoint(x: 300, y: 200))
        m.dragEnded(screenID: 0, location: CGPoint(x: 300, y: 200))
        // First click of the pair: nothing yet.
        m.dragChanged(screenID: 0, location: CGPoint(x: 150, y: 150))
        m.dragEnded(screenID: 0, location: CGPoint(x: 150, y: 150), clickCount: 1)
        #expect(finished == nil)
        m.dragChanged(screenID: 0, location: CGPoint(x: 150, y: 150))
        m.dragEnded(screenID: 0, location: CGPoint(x: 150, y: 150), clickCount: 2)
        #expect(finished == .some(.region(screen: Self.primary, rect: CGRect(x: 100, y: 100, width: 200, height: 100))))
    }

    @Test func doubleClickOutsideTheRegionDoesNotConfirm() {
        let m = model()
        var finished: PickerSelection??
        m.onFinish = { finished = .some($0) }
        m.dragChanged(screenID: 0, location: CGPoint(x: 100, y: 100))
        m.dragChanged(screenID: 0, location: CGPoint(x: 300, y: 200))
        m.dragEnded(screenID: 0, location: CGPoint(x: 300, y: 200))
        m.dragChanged(screenID: 0, location: CGPoint(x: 600, y: 600))
        m.dragEnded(screenID: 0, location: CGPoint(x: 600, y: 600), clickCount: 2)
        #expect(finished == nil)
        #expect(m.regionRect(on: 0) == nil)
    }

    @Test func regionStaysInsideTheScreen() {
        let m = model()
        m.dragChanged(screenID: 0, location: CGPoint(x: 900, y: 700))
        m.dragChanged(screenID: 0, location: CGPoint(x: 1500, y: 1500))
        m.dragEnded(screenID: 0, location: CGPoint(x: 1500, y: 1500))
        #expect(m.regionRect(on: 0) == CGRect(x: 900, y: 700, width: 100, height: 100))
    }

    @Test func shiftSnapsTo16by9() {
        let m = model()
        m.snapToAspect = true
        m.dragChanged(screenID: 0, location: .zero)
        m.dragChanged(screenID: 0, location: CGPoint(x: 320, y: 100))
        m.dragEnded(screenID: 0, location: CGPoint(x: 320, y: 100))
        // Height wins: 100 rows fit 178 columns at 16:9 (rounded to whole points).
        #expect(m.regionRect(on: 0) == CGRect(x: 0, y: 0, width: 178, height: 100))
    }

    @Test func windowModePicksTheFrontmostWindowUnderTheMouseAndClickConfirms() {
        let m = model(mode: .window)
        var finished: PickerSelection??
        m.onFinish = { finished = .some($0) }
        m.hoverChanged(screenID: 0, location: CGPoint(x: 150, y: 150))
        #expect(m.hoveredWindow == Self.front)
        #expect(m.hoveredWindowRect(on: 0) == Self.front.frame)
        #expect(m.hoveredWindowRect(on: 1) == nil)
        m.hoverChanged(screenID: 0, location: CGPoint(x: 60, y: 400))
        #expect(m.hoveredWindow == Self.back)
        m.dragChanged(screenID: 0, location: CGPoint(x: 60, y: 400))
        m.dragEnded(screenID: 0, location: CGPoint(x: 60, y: 400))
        #expect(finished == .some(.window(Self.back)))
    }

    @Test func windowRectsUseTheScreensOwnCoordinates() {
        let m = model(mode: .window)
        let onSecond = PickerWindow(id: 12, frame: CGRect(x: 1100, y: 200, width: 200, height: 100), title: "", appName: "")
        m.windows = [onSecond]
        m.hoverChanged(screenID: 1, location: CGPoint(x: 150, y: 150))
        #expect(m.hoveredWindow == onSecond)
        #expect(m.hoveredWindowRect(on: 1) == CGRect(x: 100, y: 100, width: 200, height: 100))
    }

    @Test func screenModeSelectsTheHoveredScreen() {
        let m = model(mode: .screen)
        m.hoverChanged(screenID: 1, location: CGPoint(x: 10, y: 10))
        #expect(m.selection == .screen(Self.second))
        #expect(m.dimensionLabel == "800 × 600")
        m.hoverChanged(screenID: 1, location: nil)
        #expect(m.selection == nil)
    }

    @Test func cancelReportsNilOnce() {
        let m = model()
        var calls = 0
        m.onFinish = { if $0 == nil { calls += 1 } }
        m.cancel()
        m.cancel()
        m.confirm()
        #expect(calls == 1)
    }

    @Test func switchingModeKeepsTheRegionForLater() {
        let m = model()
        m.dragChanged(screenID: 0, location: .zero)
        m.dragChanged(screenID: 0, location: CGPoint(x: 100, y: 100))
        m.dragEnded(screenID: 0, location: CGPoint(x: 100, y: 100))
        m.setMode(.screen)
        #expect(m.selection == nil)
        m.setMode(.region)
        #expect(m.selection == .region(screen: Self.primary, rect: CGRect(x: 0, y: 0, width: 100, height: 100)))
    }
}
