import Foundation
import Testing
@testable import DeskpouchCore

@MainActor
struct ToolSwitchesTests {
    func freshDefaults() -> UserDefaults {
        let name = "ToolSwitchesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func everyToolIsOnWhenNothingIsStored() {
        let switches = ToolSwitches(defaults: freshDefaults())
        #expect(switches.isEnabled("voice"))
        #expect(switches.isEnabled("a-tool-from-a-later-build"))
    }

    @Test func switchingOffPersistsAndOnClearsIt() {
        let defaults = freshDefaults()
        ToolSwitches(defaults: defaults).set("screen", enabled: false)
        let reloaded = ToolSwitches(defaults: defaults)
        #expect(!reloaded.isEnabled("screen"))
        #expect(reloaded.isEnabled("voice"))
        reloaded.set("screen", enabled: true)
        #expect(ToolSwitches(defaults: defaults).isEnabled("screen"))
    }
}
