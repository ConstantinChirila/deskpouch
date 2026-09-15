import AppKit
import SwiftUI

/// What a shortcut row records: a single modifier held down, or a key with modifiers pressed once.
public enum ShortcutKind: Sendable, Equatable {
    case hold(ModifierKey)
    case press(KeyCombo)

    var symbols: [String] {
        switch self {
        case .hold(let key): [key.symbol]
        case .press(let combo): combo.symbols
        }
    }
}

/// Keycaps showing the current shortcut. Click to record: the next modifier (hold) or key combo (press) replaces it.
/// Escape cancels. Recording uses a local key monitor, so the panel has to be the key window.
public struct ShortcutRecorder: View {
    let kind: ShortcutKind
    let onChange: @MainActor (ShortcutKind) -> Void
    @State private var recording = false
    @State private var monitor: Any?

    public init(_ kind: ShortcutKind, onChange: @escaping @MainActor (ShortcutKind) -> Void) {
        self.kind = kind
        self.onChange = onChange
    }

    public var body: some View {
        Button {
            recording ? stop() : start()
        } label: {
            HStack(spacing: 6) {
                if recording {
                    Keycap("…", width: 42)
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.Radius.keycap, style: .continuous)
                                .strokeBorder(Theme.Colors.accent(0.6), lineWidth: 1)
                        )
                } else {
                    HStack(spacing: 4) {
                        ForEach(Array(kind.symbols.enumerated()), id: \.offset) { _, symbol in
                            Keycap(symbol, width: kind.symbols.count == 1 ? 42 : nil)
                        }
                    }
                }
                Text(hint).font(.dp(11)).foregroundStyle(recording ? Theme.Colors.accentHigh : Theme.Colors.textTertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onDisappear { stop() }
    }

    private var hint: String {
        guard recording else { return "click to change" }
        switch kind {
        case .hold: return "press a modifier · esc cancels"
        case .press: return "press keys · esc cancels"
        }
    }

    private func start() {
        recording = true
        let mask: NSEvent.EventTypeMask
        switch kind {
        case .hold: mask = [.flagsChanged, .keyDown]
        case .press: mask = .keyDown
        }
        monitor = NSEvent.addLocalMonitorForEvents(matching: mask) { event in
            handle(event)
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
    }

    /// Returns nil to swallow the event.
    private func handle(_ event: NSEvent) -> NSEvent? {
        if event.type == .keyDown, event.keyCode == 53 { // Escape
            stop()
            return nil
        }
        switch kind {
        case .hold:
            guard event.type == .flagsChanged, let key = ModifierKey(rawValue: event.keyCode),
                  ModifierHoldDetector.isDown(key, in: event.cgEvent?.flags ?? []) else { return nil }
            stop()
            onChange(.hold(key))
            return nil
        case .press:
            guard event.type == .keyDown else { return nil }
            var modifiers: KeyCombo.Modifiers = []
            let flags = event.modifierFlags
            if flags.contains(.command) { modifiers.insert(.command) }
            if flags.contains(.shift) { modifiers.insert(.shift) }
            if flags.contains(.option) { modifiers.insert(.option) }
            if flags.contains(.control) { modifiers.insert(.control) }
            // A bare key would fire while typing anywhere; ask for at least one of ⌘ ⌥ ⌃.
            guard !modifiers.isDisjoint(with: [.command, .option, .control]) else { return nil }
            stop()
            onChange(.press(KeyCombo(keyCode: event.keyCode, modifiers: modifiers)))
            return nil
        }
    }
}
