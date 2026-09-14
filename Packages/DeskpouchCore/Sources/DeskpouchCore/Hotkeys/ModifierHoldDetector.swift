import CoreGraphics

public enum HotkeyPhase: Sendable, Equatable {
    case pressed
    case released
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

    /// True when the generic flag is set and, if the keyboard reports side bits at all, this side's bit is set.
    static func isDown(_ key: ModifierKey, in flags: CGEventFlags) -> Bool {
        guard flags.contains(key.flag) else { return false }
        let familyBits = flags.rawValue & key.familyDeviceMask
        if familyBits == 0 { return true }
        return flags.rawValue & key.deviceMask != 0
    }
}
