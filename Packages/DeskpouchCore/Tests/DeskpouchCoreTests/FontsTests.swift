import AppKit
import Testing
@testable import DeskpouchCore

@MainActor
struct FontsTests {
    @Test func bundledGeistRegisters() {
        Fonts.registerBundled()
        #expect(Fonts.isAvailable)
        for name in ["Geist-Regular", "Geist-Medium", "Geist-SemiBold"] {
            #expect(NSFont(name: name, size: 13) != nil, "\(name) missing")
        }
    }
}
