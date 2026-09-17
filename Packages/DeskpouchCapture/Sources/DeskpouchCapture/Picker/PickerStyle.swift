import DeskpouchCore
import SwiftUI

/// How the picker reads for the tool that opened it: one chrome, reused across every capture tool, tinted and
/// labelled per tool. The recorder keeps amber (`.record`, the existing look); a still capture reads mint
/// (`.still`); OCR gets its own case (`.text`, plan 02) ahead of that tool landing.
public enum PickerStyle: Sendable, Equatable, CaseIterable {
    case record
    case still
    case text

    /// Selection border, dimension chip, active mode segment and the toolbar's primary button.
    public var tint: Color {
        switch self {
        case .record: Theme.Colors.accent
        case .still, .text: Theme.Colors.ok
        }
    }

    /// Top-to-bottom gradient for the active mode segment. Record keeps its amber highlight/shadow pair; `Theme`
    /// has no mint equivalent of `accentHigh`/`accentLow` yet, so still and text fall back to a flat tint (worth
    /// adding to Core if the flat fill reads wrong next to the amber one).
    var tintGradient: [Color] {
        switch self {
        case .record: [Theme.Colors.accentHigh, Theme.Colors.accentLow]
        case .still, .text: [tint, tint]
        }
    }

    /// Toolbar's primary button label: "Record" starts a recording, "Capture" grabs a still.
    public var toolbarLabel: String {
        switch self {
        case .record: "Record"
        case .still, .text: "Capture"
        }
    }

    /// Only the recorder offers system audio and microphone toggles; a still capture has no audio to control.
    public var showsAudioToggles: Bool { self == .record }
}
