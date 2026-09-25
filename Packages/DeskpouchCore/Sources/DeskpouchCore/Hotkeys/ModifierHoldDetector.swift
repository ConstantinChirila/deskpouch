import CoreGraphics

public enum HotkeyPhase: Sendable, Equatable {
    case pressed
    case released
    /// Another key was typed while the modifier was down: it was part of a chord, not a hold. No release follows.
    case cancelled
}

/// Turns a stream of `flagsChanged` events into press/release for one modifier key.
/// Pure state machine so it can be unit tested without an event tap.
public struct ModifierHoldDetector: Sendable, Equatable {
    public let key: ModifierKey
    public private(set) var isDown = false

    public init(key: ModifierKey) {
        self.key = key
    }

    /// Feed one `flagsChanged` event. Returns a phase when the key's state changed.
    public mutating func handle(keyCode: UInt16, flags: CGEventFlags) -> HotkeyPhase? {
        guard keyCode == key.rawValue else { return nil }
        let down = Self.isDown(key, in: flags)
        switch (isDown, down) {
        case (false, true):
            isDown = true
            return .pressed
        case (true, false):
            isDown = false
            return .released
        default:
            return nil
        }
    }

    /// Feed one `keyDown` from any key. A key typed during the hold turns the hold into a chord (Option + e),
    /// so the hold is dropped and the coming release is ignored.
    public mutating func handleKeyDown() -> HotkeyPhase? {
        guard isDown else { return nil }
        isDown = false
        return .cancelled
    }

    /// Feed the real state of the key's flag, polled while the key counts as down. A release the event stream
    /// never delivered (Secure Input, focus moving into a password field) still ends the hold. Both sides of a
    /// pair share the flag, so only a flag that is gone entirely counts.
    public mutating func reconcile(flagStillDown: Bool) -> HotkeyPhase? {
        guard isDown, !flagStillDown else { return nil }
        isDown = false
        return .released
    }

    /// True when the generic flag is set and, if the keyboard reports side bits at all, this side's bit is set.
    static func isDown(_ key: ModifierKey, in flags: CGEventFlags) -> Bool {
        guard flags.contains(key.flag) else { return false }
        let familyBits = flags.rawValue & key.familyDeviceMask
        if familyBits == 0 { return true }
        return flags.rawValue & key.deviceMask != 0
    }
}
