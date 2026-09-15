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
    /// What the recorder is doing; drives the menubar timer and the screen card.
    var activity: ToolActivity = .idle
    var screenKey: KeyCombo = .commandShift6
    /// Settings line in the screen card, e.g. "1080p · system audio".
    var screenStatus = "1080p · 60 fps · system audio"
    /// The recorder's key combo could not be registered (another app owns it).
    var screenKeyTaken = false
    /// 20 bar meter in the voice card, fed from the overlay's ticks.
    let panelMeter = LevelMeterModel(barCount: 20)
    /// Per-tool after-capture actions. The chips row reads and writes through `Shell`.
    let output: OutputSettings
    /// Last few history items, newest first, and the total count.
    var recent: [HistoryItem] = []
    var historyCount = 0
    var version = "0.1.0"

    init(output: OutputSettings = OutputSettings()) {
        self.output = output
    }
}
