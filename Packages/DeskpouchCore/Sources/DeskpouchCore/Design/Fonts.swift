import AppKit
import CoreText
import SwiftUI

/// Geist (OFL) bundled with Core. Falls back to SF Pro when registration fails.
@MainActor
public enum Fonts {
    public enum Weight: Sendable {
        case regular, medium, semibold

        var postScriptName: String {
            switch self {
            case .regular: "Geist-Regular"
            case .medium: "Geist-Medium"
            case .semibold: "Geist-SemiBold"
            }
        }

        var system: Font.Weight {
            switch self {
            case .regular: .regular
            case .medium: .medium
            case .semibold: .semibold
            }
        }
    }

    private static let files = ["Geist-Regular", "Geist-Medium", "Geist-SemiBold"]
    private static var didRegister = false
    private(set) static var isAvailable = false

    /// Registers the bundled Geist faces for this process. Safe to call more than once.
    public static func registerBundled() {
        guard !didRegister else { return }
        didRegister = true
        for file in files {
            guard let url = Bundle.module.url(forResource: file, withExtension: "otf", subdirectory: "Fonts") else {
                continue
            }
            var error: Unmanaged<CFError>?
            if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
                // Already registered by another bundle is fine; anything else falls back to SF.
                _ = error?.takeRetainedValue()
            }
        }
        isAvailable = files.allSatisfy { NSFont(name: $0, size: 13) != nil }
    }

    public static func nsFont(_ size: CGFloat, _ weight: Weight = .regular) -> NSFont {
        if isAvailable, let font = NSFont(name: weight.postScriptName, size: size) {
            return font
        }
        let nsWeight: NSFont.Weight = switch weight {
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        }
        return NSFont.systemFont(ofSize: size, weight: nsWeight)
    }
}

extension Font {
    /// Deskpouch type: Geist at the given size and weight, SF Pro fallback.
    @MainActor
    public static func dp(_ size: CGFloat, _ weight: Fonts.Weight = .regular) -> Font {
        if Fonts.isAvailable {
            return .custom(weight.postScriptName, size: size)
        }
        return .system(size: size, weight: weight.system)
    }
}
