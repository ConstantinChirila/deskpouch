import AppKit
import SwiftUI
import Testing
@testable import DeskpouchCore

/// Not an assertion suite. Set DESKPOUCH_SNAPSHOT_DIR to dump PNGs of Core components for eyeballing against the mocks.
@MainActor
struct SnapshotDumpTests {
    @Test func dumpComponents() throws {
        guard let dir = ProcessInfo.processInfo.environment["DESKPOUCH_SNAPSHOT_DIR"] else { return }
        Fonts.registerBundled()
        let out = URL(fileURLWithPath: dir, isDirectory: true)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

        let meter = LevelMeterModel(barCount: 25)
        var source: Float = 0
        for i in 0..<25 {
            source = [0.1, 0.35, 0.7, 1.0, 0.5, 0.25, 0.8, 0.95, 0.55, 0.4][i % 10]
            meter.push(level: source, dt: 1 / 30)
        }

        try write(ListeningPill(meter: meter, elapsed: 4).padding(60).background(Theme.Colors.bg), to: out, "pill-listening")
        try write(
            HStack(spacing: 12) {
                Keycap("⌥", size: .large, width: 42)
                Keycap("⌘"); Keycap("⇧"); Keycap("6")
            }.padding(24).background(Theme.Colors.bg),
            to: out, "keycaps"
        )
        try write(
            HStack(spacing: 20) {
                MicIcon().stroke(style: .icon(1.7)).frame(width: 64, height: 64)
                PouchIcon().stroke(style: .icon(1.6)).frame(width: 64, height: 64)
                GearIcon().stroke(style: .icon(1.5)).frame(width: 64, height: 64)
            }.foregroundStyle(Theme.Colors.text).padding(24).background(Theme.Colors.bg),
            to: out, "icons"
        )

        try writeImage(MenubarIcon.idle(), scale: 6, to: out, "menubar-idle", template: true)
        for glyph in MenubarGlyph.allCases {
            try writeImage(glyph.image(), scale: 6, to: out, "glyph-\(glyph.rawValue)", template: true)
        }
        try writeMenubarStrip(to: out)
        try writeImage(MenubarIcon.listening(levels: Array(meter.bars.suffix(7))), scale: 6, to: out, "menubar-listening", template: false)
    }

    private func write(_ view: some View, to dir: URL, _ name: String) throws {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.nsImage else { throw SnapshotError.render(name) }
        try save(image, to: dir.appending(path: "\(name).png"))
    }

    private func writeImage(_ image: NSImage, scale: CGFloat, to dir: URL, _ name: String, template: Bool) throws {
        let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        let canvas = NSImage(size: size, flipped: false) { rect in
            (template ? NSColor.white : NSColor(hex: 0x0D12_11)).setFill()
            rect.fill()
            if template {
                NSColor.black.set()
            }
            image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
            return true
        }
        try save(canvas, to: dir.appending(path: "\(name).png"))
    }

    private func save(_ image: NSImage, to url: URL) throws {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            throw SnapshotError.encode(url.lastPathComponent)
        }
        try png.write(to: url)
    }

    enum SnapshotError: Error { case render(String), encode(String) }

    /// A dark and a light menubar strip with the current glyph and every candidate at 1x and 2x, as macOS would tint them.
    private func writeMenubarStrip(to out: URL) throws {
        let glyphs: [(String, NSImage)] = MenubarGlyph.allCases.map { ($0.rawValue, $0.image()) }
        for (name, dark) in [("dark", true), ("light", false)] {
            for scale in [1, 2] {
                let cell: CGFloat = 40
                let size = NSSize(width: cell * CGFloat(glyphs.count) + 20, height: 24)
                let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width) * scale, pixelsHigh: Int(size.height) * scale,
                                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
                rep.size = size
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
                (dark ? NSColor(white: 0.12, alpha: 1) : NSColor(white: 0.93, alpha: 1)).setFill()
                NSRect(origin: .zero, size: size).fill()
                for (i, (_, image)) in glyphs.enumerated() {
                    let tinted = image.copy() as! NSImage
                    tinted.isTemplate = false
                    let rect = NSRect(x: 10 + cell * CGFloat(i) + (cell - 18) / 2, y: 3, width: 18, height: 18)
                    tinted.lockFocus()
                    (dark ? NSColor.white : NSColor.black).set()
                    NSRect(origin: .zero, size: tinted.size).fill(using: .sourceAtop)
                    tinted.unlockFocus()
                    tinted.draw(in: rect)
                }
                NSGraphicsContext.restoreGraphicsState()
                try rep.representation(using: .png, properties: [:])?.write(to: out.appending(path: "menubar-strip-\(name)-\(scale)x.png"))
            }
        }
    }
}
