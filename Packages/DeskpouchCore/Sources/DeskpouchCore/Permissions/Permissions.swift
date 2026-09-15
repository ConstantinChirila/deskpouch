import AppKit
import ApplicationServices
import AVFoundation
import CoreGraphics

/// TCC checks and prompts. Prompted on first use per tool, never at launch.
@MainActor
public enum Permissions {
    /// Accessibility (kTCCServiceAccessibility). Needed to post paste events and, in practice, for keyboard event taps.
    public static var accessibilityGranted: Bool {
        AXIsProcessTrusted()
    }

    /// Input Monitoring (kTCCServiceListenEvent). What a listen-only keyboard tap formally requires.
    public static var inputMonitoringGranted: Bool {
        CGPreflightListenEventAccess()
    }

    /// True when a keyboard event tap can be created.
    public static var canListenToKeyboard: Bool {
        accessibilityGranted || inputMonitoringGranted
    }

    /// Shows the system Accessibility prompt once per app identity.
    public static func requestAccessibility() {
        // Literal value of kAXTrustedCheckOptionPrompt; the global is not concurrency-safe under Swift 6.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// Shows the system Input Monitoring prompt once per app identity.
    @discardableResult
    public static func requestInputMonitoring() -> Bool {
        CGRequestListenEventAccess()
    }

    public enum MicrophoneStatus: Sendable { case granted, denied, undetermined }

    public static var microphone: MicrophoneStatus {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: .granted
        case .notDetermined: .undetermined
        default: .denied
        }
    }

    /// Shows the system microphone prompt when undetermined. Returns the resulting grant.
    public static func requestMicrophone() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    public static func openMicrophoneSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
    }

    public static func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    public static func openInputMonitoringSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
    }

    private static func open(_ string: String) {
        guard let url = URL(string: string) else { return }
        NSWorkspace.shared.open(url)
    }
}
