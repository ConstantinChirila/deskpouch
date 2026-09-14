import DeskpouchCore
import Observation

/// What the menubar panel shows. Written by `Shell`, read by SwiftUI.
@MainActor
@Observable
final class ShellState {
    var isListening = false
    /// The event tap is live and the hold key will fire.
    var hotkeyReady = false
    var holdKey: ModifierKey = .rightOption
    var version = "0.1.0"
}
