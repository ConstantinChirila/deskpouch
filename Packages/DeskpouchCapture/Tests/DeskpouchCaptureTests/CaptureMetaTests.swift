import CoreGraphics
import DeskpouchCore
import Testing
@testable import DeskpouchCapture

struct CaptureMetaTests {
    // Primary 1000x800 at origin, a second screen to its right, 100 pt down.
    static let primary = PickerScreen(id: 0, displayID: 1, frame: CGRect(x: 0, y: 0, width: 1000, height: 800),
                                      cgFrame: CGRect(x: 0, y: 0, width: 1000, height: 800), backingScale: 2)
    static let second = PickerScreen(id: 1, displayID: 2, frame: CGRect(x: 1000, y: 100, width: 800, height: 600),
                                     cgFrame: CGRect(x: 1000, y: 100, width: 800, height: 600), backingScale: 1)
    static let screens = [primary, second]

    @Test func regionKeepsItsScreenLocalRect() {
        let selection = PickerSelection.region(screen: Self.second, rect: CGRect(x: 40, y: 60, width: 320, height: 200))
        #expect(selection.captureMeta(screens: Self.screens) == ResultMeta(display: 2, rect: [40, 60, 320, 200]))
    }

    @Test func screenIsTheWholeDisplay() {
        #expect(PickerSelection.screen(Self.second).captureMeta(screens: Self.screens) == ResultMeta(display: 2, rect: [0, 0, 800, 600]))
    }

    @Test func windowIsLocalToTheDisplayItSitsOn() {
        let window = PickerWindow(id: 12, frame: CGRect(x: 1100, y: 200, width: 200, height: 100), title: "", appName: "")
        #expect(PickerSelection.window(window).captureMeta(screens: Self.screens) == ResultMeta(display: 2, rect: [100, 100, 200, 100]))
    }

    @Test func windowAcrossDisplaysIsClippedToTheOneHoldingMostOfIt() {
        // 100 pt on the primary, 300 pt on the second.
        let window = PickerWindow(id: 13, frame: CGRect(x: 900, y: 200, width: 400, height: 100), title: "", appName: "")
        #expect(PickerSelection.window(window).captureMeta(screens: Self.screens) == ResultMeta(display: 2, rect: [0, 100, 300, 100]))
    }

    @Test func windowOffEveryDisplayHasNoMeta() {
        let window = PickerWindow(id: 14, frame: CGRect(x: 5000, y: 5000, width: 200, height: 100), title: "", appName: "")
        #expect(PickerSelection.window(window).captureMeta(screens: Self.screens) == nil)
    }
}
