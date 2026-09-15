import Carbon.HIToolbox
import Foundation

/// A key plus modifiers, pressed once to act (as opposed to a `ModifierKey` hold).
public struct KeyCombo: Hashable, Codable, Sendable {
    public struct Modifiers: OptionSet, Hashable, Codable, Sendable {
        public let rawValue: UInt8
        public init(rawValue: UInt8) { self.rawValue = rawValue }

        public static let control = Modifiers(rawValue: 1 << 0)
        public static let option = Modifiers(rawValue: 1 << 1)
        public static let shift = Modifiers(rawValue: 1 << 2)
        public static let command = Modifiers(rawValue: 1 << 3)

        /// Keycap order. Apple prints ⇧⌘; the design mocks print ⌘⇧ and the keycaps follow the mocks.
        static let displayOrder: [(Modifiers, String)] = [
            (.control, "⌃"), (.option, "⌥"), (.command, "⌘"), (.shift, "⇧"),
        ]
    }

    /// Virtual key code (kVK_*), layout independent.
    public var keyCode: UInt16
    public var modifiers: Modifiers

    public init(keyCode: UInt16, modifiers: Modifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// ⌘⇧6: the screen recorder's default.
    public static let commandShift6 = KeyCombo(keyCode: UInt16(kVK_ANSI_6), modifiers: [.command, .shift])

    /// One entry per keycap, modifiers first: ["⌘", "⇧", "6"].
    public var symbols: [String] {
        Modifiers.displayOrder.compactMap { modifiers.contains($0.0) ? $0.1 : nil } + [keyLabel]
    }

    /// "⌘⇧6".
    public var display: String { symbols.joined() }

    /// Label for the non-modifier key. "?" for keys outside the table.
    public var keyLabel: String {
        Self.keyLabels[keyCode] ?? "?"
    }

    /// Modifier bits as Carbon's RegisterEventHotKey wants them.
    public var carbonModifiers: UInt32 {
        var bits: UInt32 = 0
        if modifiers.contains(.command) { bits |= UInt32(cmdKey) }
        if modifiers.contains(.shift) { bits |= UInt32(shiftKey) }
        if modifiers.contains(.option) { bits |= UInt32(optionKey) }
        if modifiers.contains(.control) { bits |= UInt32(controlKey) }
        return bits
    }

    /// ANSI layout labels for the common keys. Layout differences only affect the label, never what fires.
    static let keyLabels: [UInt16: String] = {
        var table: [UInt16: String] = [:]
        let letters: [(Int, String)] = [
            (kVK_ANSI_A, "A"), (kVK_ANSI_B, "B"), (kVK_ANSI_C, "C"), (kVK_ANSI_D, "D"), (kVK_ANSI_E, "E"),
            (kVK_ANSI_F, "F"), (kVK_ANSI_G, "G"), (kVK_ANSI_H, "H"), (kVK_ANSI_I, "I"), (kVK_ANSI_J, "J"),
            (kVK_ANSI_K, "K"), (kVK_ANSI_L, "L"), (kVK_ANSI_M, "M"), (kVK_ANSI_N, "N"), (kVK_ANSI_O, "O"),
            (kVK_ANSI_P, "P"), (kVK_ANSI_Q, "Q"), (kVK_ANSI_R, "R"), (kVK_ANSI_S, "S"), (kVK_ANSI_T, "T"),
            (kVK_ANSI_U, "U"), (kVK_ANSI_V, "V"), (kVK_ANSI_W, "W"), (kVK_ANSI_X, "X"), (kVK_ANSI_Y, "Y"),
            (kVK_ANSI_Z, "Z"),
            (kVK_ANSI_0, "0"), (kVK_ANSI_1, "1"), (kVK_ANSI_2, "2"), (kVK_ANSI_3, "3"), (kVK_ANSI_4, "4"),
            (kVK_ANSI_5, "5"), (kVK_ANSI_6, "6"), (kVK_ANSI_7, "7"), (kVK_ANSI_8, "8"), (kVK_ANSI_9, "9"),
            (kVK_ANSI_Minus, "-"), (kVK_ANSI_Equal, "="), (kVK_ANSI_LeftBracket, "["), (kVK_ANSI_RightBracket, "]"),
            (kVK_ANSI_Semicolon, ";"), (kVK_ANSI_Quote, "'"), (kVK_ANSI_Comma, ","), (kVK_ANSI_Period, "."),
            (kVK_ANSI_Slash, "/"), (kVK_ANSI_Backslash, "\\"), (kVK_ANSI_Grave, "`"),
            (kVK_Space, "␣"), (kVK_Return, "↩"), (kVK_Tab, "⇥"), (kVK_Delete, "⌫"), (kVK_Escape, "⎋"),
            (kVK_LeftArrow, "←"), (kVK_RightArrow, "→"), (kVK_UpArrow, "↑"), (kVK_DownArrow, "↓"),
            (kVK_F1, "F1"), (kVK_F2, "F2"), (kVK_F3, "F3"), (kVK_F4, "F4"), (kVK_F5, "F5"), (kVK_F6, "F6"),
            (kVK_F7, "F7"), (kVK_F8, "F8"), (kVK_F9, "F9"), (kVK_F10, "F10"), (kVK_F11, "F11"), (kVK_F12, "F12"),
        ]
        for (code, label) in letters { table[UInt16(code)] = label }
        return table
    }()
}
