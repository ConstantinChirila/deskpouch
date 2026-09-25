import Carbon.HIToolbox
import Foundation

/// What `HotkeyCenter` needs from the system's combo hotkeys. Tests swap in a fake.
@MainActor
protocol PressHotkeys: AnyObject {
    func register(_ combo: KeyCombo, handler: @escaping @MainActor () -> Void) -> UInt32?
    func unregister(_ id: UInt32)
}

/// Key-combo hotkeys through Carbon's RegisterEventHotKey. Unlike the event monitors used for modifier holds,
/// these need no Accessibility grant and the key press never reaches the frontmost app.
@MainActor
final class CarbonHotkeys: PressHotkeys {
    static let shared = CarbonHotkeys()

    private static let signature: OSType = 0x4450_4348 // 'DPCH'
    private var handlers: [UInt32: @MainActor () -> Void] = [:]
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var nextID: UInt32 = 1
    private var handlerRef: EventHandlerRef?

    private init() {}

    /// Returns the registration id, or nil when the system refused the key (another app owns it).
    func register(_ combo: KeyCombo, handler: @escaping @MainActor () -> Void) -> UInt32? {
        installHandlerIfNeeded()
        let id = nextID
        nextID += 1
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        let status = RegisterEventHotKey(
            UInt32(combo.keyCode), combo.carbonModifiers, hotKeyID, GetEventDispatcherTarget(), 0, &ref
        )
        guard status == noErr, let ref else {
            hotkeyLog.error("RegisterEventHotKey failed for \(combo.display, privacy: .public): \(status)")
            return nil
        }
        handlers[id] = handler
        refs[id] = ref
        hotkeyLog.info("registered \(combo.display, privacy: .public)")
        return id
    }

    func unregister(_ id: UInt32) {
        if let ref = refs.removeValue(forKey: id) { UnregisterEventHotKey(ref) }
        handlers[id] = nil
    }

    fileprivate func fire(_ id: UInt32) {
        handlers[id]?()
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        // The dispatcher target delivers on the main thread, so hopping to the main actor is a formality.
        InstallEventHandler(GetEventDispatcherTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID
            )
            guard status == noErr, hotKeyID.signature == CarbonHotkeys.signature else { return OSStatus(eventNotHandledErr) }
            MainActor.assumeIsolated { CarbonHotkeys.shared.fire(hotKeyID.id) }
            return noErr
        }, 1, &spec, nil, &handlerRef)
    }
}
