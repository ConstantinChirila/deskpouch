import CoreGraphics
import Testing
@testable import DeskpouchCore

struct ModifierHoldDetectorTests {
    let rightOption = ModifierKey.rightOption.rawValue
    let leftOption = ModifierKey.leftOption.rawValue

    private func flags(_ generic: CGEventFlags, device: UInt64 = 0) -> CGEventFlags {
        CGEventFlags(rawValue: generic.rawValue | device)
    }

    @Test func pressThenRelease() {
        var d = ModifierHoldDetector(key: .rightOption)
        #expect(d.handle(keyCode: rightOption, flags: flags(.maskAlternate, device: 0x40)) == .pressed)
        #expect(d.isDown)
        #expect(d.handle(keyCode: rightOption, flags: flags([], device: 0)) == .released)
        #expect(!d.isDown)
    }

    @Test func repeatedPressIsIgnored() {
        var d = ModifierHoldDetector(key: .rightOption)
        #expect(d.handle(keyCode: rightOption, flags: flags(.maskAlternate, device: 0x40)) == .pressed)
        #expect(d.handle(keyCode: rightOption, flags: flags(.maskAlternate, device: 0x40)) == nil)
    }

    @Test func keyDownDuringHoldCancelsAndSwallowsRelease() {
        var d = ModifierHoldDetector(key: .rightOption)
        #expect(d.handle(keyCode: rightOption, flags: flags(.maskAlternate, device: 0x40)) == .pressed)
        #expect(d.handleKeyDown() == .cancelled)
        #expect(!d.isDown)
        #expect(d.handleKeyDown() == nil)
        #expect(d.handle(keyCode: rightOption, flags: flags([])) == nil)
    }

    @Test func keyDownWithoutHoldIsIgnored() {
        var d = ModifierHoldDetector(key: .rightOption)
        #expect(d.handleKeyDown() == nil)
    }

    @Test func releaseWithoutPressIsIgnored() {
        var d = ModifierHoldDetector(key: .rightOption)
        #expect(d.handle(keyCode: rightOption, flags: flags([])) == nil)
    }

    @Test func otherKeysAreIgnored() {
        var d = ModifierHoldDetector(key: .rightOption)
        #expect(d.handle(keyCode: leftOption, flags: flags(.maskAlternate, device: 0x20)) == nil)
        #expect(d.handle(keyCode: 0, flags: flags(.maskCommand)) == nil)
        #expect(!d.isDown)
    }

    @Test func leftSideStillHeldDoesNotCountAsRightDown() {
        // Right option key code arrives with only the left device bit set.
        var d = ModifierHoldDetector(key: .rightOption)
        #expect(d.handle(keyCode: rightOption, flags: flags(.maskAlternate, device: 0x20)) == nil)
    }

    @Test func keyboardsWithoutSideBitsStillWork() {
        var d = ModifierHoldDetector(key: .rightOption)
        #expect(d.handle(keyCode: rightOption, flags: flags(.maskAlternate)) == .pressed)
        #expect(d.handle(keyCode: rightOption, flags: flags([])) == .released)
    }

    @Test func otherModifiersDuringHoldDoNotRelease() {
        var d = ModifierHoldDetector(key: .rightOption)
        #expect(d.handle(keyCode: rightOption, flags: flags(.maskAlternate, device: 0x40)) == .pressed)
        // Shift pressed while option held: event carries shift's key code.
        #expect(d.handle(keyCode: ModifierKey.leftShift.rawValue, flags: flags([.maskAlternate, .maskShift], device: 0x42)) == nil)
        #expect(d.isDown)
    }
}
