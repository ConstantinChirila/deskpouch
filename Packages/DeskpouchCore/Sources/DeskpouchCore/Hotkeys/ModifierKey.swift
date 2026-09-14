import CoreGraphics

/// A single physical modifier key, identified by its virtual key code.
public enum ModifierKey: UInt16, Sendable, CaseIterable, Codable, Hashable {
    case leftCommand = 55
    case rightCommand = 54
    case leftShift = 56
    case rightShift = 60
    case leftOption = 58
    case rightOption = 61
    case leftControl = 59
    case rightControl = 62
    case function = 63

    /// Generic modifier flag, set while either side of the pair is down.
    public var flag: CGEventFlags {
        switch self {
        case .leftCommand, .rightCommand: .maskCommand
        case .leftShift, .rightShift: .maskShift
        case .leftOption, .rightOption: .maskAlternate
        case .leftControl, .rightControl: .maskControl
        case .function: .maskSecondaryFn
        }
    }

    /// Device-specific bit for this exact key (NX_DEVICE*KEYMASK from IOKit/hidsystem/IOLLEvent.h).
    /// Zero when the key has no side-specific bit.
    public var deviceMask: UInt64 {
        switch self {
        case .leftControl: 0x0000_0001
        case .leftShift: 0x0000_0002
        case .rightShift: 0x0000_0004
        case .leftCommand: 0x0000_0008
        case .rightCommand: 0x0000_0010
        case .leftOption: 0x0000_0020
        case .rightOption: 0x0000_0040
        case .rightControl: 0x0000_2000
        case .function: 0
        }
    }

    /// Device bits for both sides of this key's pair.
    public var familyDeviceMask: UInt64 {
        switch self {
        case .leftCommand, .rightCommand: ModifierKey.leftCommand.deviceMask | ModifierKey.rightCommand.deviceMask
        case .leftShift, .rightShift: ModifierKey.leftShift.deviceMask | ModifierKey.rightShift.deviceMask
        case .leftOption, .rightOption: ModifierKey.leftOption.deviceMask | ModifierKey.rightOption.deviceMask
        case .leftControl, .rightControl: ModifierKey.leftControl.deviceMask | ModifierKey.rightControl.deviceMask
        case .function: 0
        }
    }

    public var symbol: String {
        switch self {
        case .leftCommand, .rightCommand: "⌘"
        case .leftShift, .rightShift: "⇧"
        case .leftOption, .rightOption: "⌥"
        case .leftControl, .rightControl: "⌃"
        case .function: "fn"
        }
    }

    public var displayName: String {
        switch self {
        case .leftCommand: "Left Command"
        case .rightCommand: "Right Command"
        case .leftShift: "Left Shift"
        case .rightShift: "Right Shift"
        case .leftOption: "Left Option"
        case .rightOption: "Right Option"
        case .leftControl: "Left Control"
        case .rightControl: "Right Control"
        case .function: "Function"
        }
    }
}
