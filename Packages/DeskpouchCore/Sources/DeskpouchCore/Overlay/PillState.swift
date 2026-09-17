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
    /// Mint ring, check, "Saved", file name. `copied` adds the pasteboard hint.
    case saved(name: String, copied: Bool)
    /// Record ring, pulsing dot, timer, Stop button. `detail` is e.g. "1040 × 760 · 60 fps".
    case recording(detail: String)
    /// Mint ring, capture thumbnail, title, hint, and a button (e.g. "Annotate"). The thumbnail and the button's
    /// handler live on the controller.
    case captured(title: String, hint: String, action: String)
    /// Record ring, message.
    case failed(String)

    var isListening: Bool {
        if case .listening = self { return true }
        return false
    }

    var isRecording: Bool {
        if case .recording = self { return true }
        return false
    }

    var isCaptured: Bool {
        if case .captured = self { return true }
        return false
    }

    /// States with a button, so the pill has to take clicks.
    var isInteractive: Bool { isRecording || isCaptured }

    /// States that run the elapsed-time ticker.
    var isTimed: Bool { isListening || isRecording }
}
