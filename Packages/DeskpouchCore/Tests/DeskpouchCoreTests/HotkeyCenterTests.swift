import Testing
@testable import DeskpouchCore

/// Stands in for Carbon: hands out ids and remembers what is registered.
@MainActor
final class FakePressHotkeys: PressHotkeys {
    private(set) var registered: [UInt32: KeyCombo] = [:]
    private var handlers: [UInt32: @MainActor () -> Void] = [:]
    private var nextID: UInt32 = 100
    var refuses = false

    func register(_ combo: KeyCombo, handler: @escaping @MainActor () -> Void) -> UInt32? {
        guard !refuses else { return nil }
        nextID += 1
        registered[nextID] = combo
        handlers[nextID] = handler
        return nextID
    }

    func unregister(_ id: UInt32) {
        registered[id] = nil
        handlers[id] = nil
    }

    func fireAll() {
        for handler in handlers.values { handler() }
    }
}

@MainActor
struct HotkeyCenterTests {
    private let combo = KeyCombo(keyCode: 18, modifiers: [.command, .shift])

    @Test func startRestoresThePressesStopTookOut() {
        let carbon = FakePressHotkeys()
        let center = HotkeyCenter(carbon: carbon)
        var fired = 0
        let registration = center.registerPress(combo) { fired += 1 }
        #expect(registration != nil)
        center.stop()
        #expect(carbon.registered.isEmpty)
        center.start()
        #expect(carbon.registered.count == 1)
        carbon.fireAll()
        #expect(fired == 1)
    }

    @Test func aRegistrationStaysValidAcrossStopAndStart() throws {
        let carbon = FakePressHotkeys()
        let center = HotkeyCenter(carbon: carbon)
        let registration = try #require(center.registerPress(combo) {})
        center.stop()
        center.start()
        center.unregister(registration)
        #expect(carbon.registered.isEmpty)
        center.start()
        #expect(carbon.registered.isEmpty)
    }

    @Test func aComboTakenWhileStoppedIsTriedAgain() {
        let carbon = FakePressHotkeys()
        let center = HotkeyCenter(carbon: carbon)
        center.registerPress(combo) {}
        center.stop()
        carbon.refuses = true
        center.start()
        #expect(carbon.registered.isEmpty)
        carbon.refuses = false
        center.start()
        #expect(carbon.registered.count == 1)
    }

    @Test func startDoesNotRegisterALivePressTwice() {
        let carbon = FakePressHotkeys()
        let center = HotkeyCenter(carbon: carbon)
        center.registerPress(combo) {}
        center.start()
        #expect(carbon.registered.count == 1)
    }
}
