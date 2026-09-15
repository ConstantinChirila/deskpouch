import Foundation

/// What the floating pill shows.
public enum PillState: Sendable, Equatable {
    case hidden
    /// Amber ring, live meter, timer.
    case listening
    /// Something is loading before work can start, e.g. a model download. Amber ring, message.
    case preparing(String)
    /// Amber ring, loader, "Transcribing". `detail` is the engine name.
    case transcribing(detail: String)
    /// Mint ring, check, "Pasted into X".
    case pasted(target: String)
    /// Mint ring, check, "Copied". Shown when there was no app to paste into.
    case copied
    /// Record ring, message.
    case failed(String)

    var isListening: Bool {
        if case .listening = self { return true }
        return false
    }
}
