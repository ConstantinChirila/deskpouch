import DeskpouchCore
import Observation

/// What the menubar panel shows. Written by `Shell`, read by SwiftUI.
@MainActor
@Observable
final class ShellState {
    var isListening = false
    /// The hold key monitors are live.
    var hotkeyReady = false
    var holdKey: ModifierKey = .rightOption
    /// Engine line in the voice card, e.g. "Parakeet v3 · local".
    var voiceStatus = "Parakeet v3"
    /// 20 bar meter in the voice card, fed from the overlay's ticks.
    let panelMeter = LevelMeterModel(barCount: 20)
    var version = "0.1.0"
}
