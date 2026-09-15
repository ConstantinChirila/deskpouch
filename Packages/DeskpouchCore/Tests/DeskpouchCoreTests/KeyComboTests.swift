import Carbon.HIToolbox
import Testing
@testable import DeskpouchCore

struct KeyComboTests {
    @Test func symbolsFollowTheMockOrder() {
        let combo = KeyCombo(keyCode: UInt16(kVK_ANSI_6), modifiers: [.shift, .command, .control])
        #expect(combo.symbols == ["⌃", "⌘", "⇧", "6"])
        #expect(combo.display == "⌃⌘⇧6")
    }

    @Test func defaultRecorderComboIsCommandShift6() {
        #expect(KeyCombo.commandShift6.display == "⌘⇧6")
        #expect(KeyCombo.commandShift6.carbonModifiers == UInt32(cmdKey | shiftKey))
    }

    @Test func unknownKeyCodeGetsPlaceholderLabel() {
        #expect(KeyCombo(keyCode: 999, modifiers: []).keyLabel == "?")
    }

    @Test func roundTripsThroughJSON() throws {
        let combo = KeyCombo(keyCode: UInt16(kVK_ANSI_R), modifiers: [.option])
        let data = try JSONEncoder().encode(combo)
        #expect(try JSONDecoder().decode(KeyCombo.self, from: data) == combo)
    }
}
