import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import DeskpouchGallery

@MainActor
struct GalleryGIFPlayerTests {
    /// `frames` grey 8x8 frames, `delay` seconds each.
    static func makeGIF(frames: Int, delay: Double) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "gallery-\(UUID().uuidString).gif")
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, frames, nil))
        for index in 0..<frames {
            let context = try #require(CGContext(
                data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.setFillColor(gray: CGFloat(index + 1) / CGFloat(frames + 1), alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
            let properties = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay, kCGImagePropertyGIFUnclampedDelayTime: delay]]
            CGImageDestinationAddImage(destination, try #require(context.makeImage()), properties as CFDictionary)
        }
        #expect(CGImageDestinationFinalize(destination))
        return url
    }

    static func waitUntil(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<200 where !condition() {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    /// The grey of a frame's first pixel, 0 to 255.
    static func grey(_ image: CGImage?) -> Int? {
        guard let image else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = CGContext(
            data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        context?.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return Int(pixel[0])
    }

    @Test func loadsPlaysScrubsAndStops() async throws {
        let url = try Self.makeGIF(frames: 4, delay: 0.1)
        defer { try? FileManager.default.removeItem(at: url) }
        let player = GalleryGIFPlayer()
        player.load(url)
        await Self.waitUntil { player.duration > 0 }
        #expect(abs(player.duration - 0.4) < 0.001)
        #expect(player.frame != nil)
        #expect(player.isPlaying)

        // It advances on its own.
        await Self.waitUntil { player.time > 0 }
        #expect(player.time > 0)

        // Scrubbing pauses on the frame under that position: 0.6 of 0.4 s is inside the third frame.
        player.scrub(to: 0.6)
        #expect(!player.isPlaying)
        #expect(abs(player.time - 0.2) < 0.001)
        player.scrub(to: 1)
        #expect(abs(player.time - 0.3) < 0.001)
        // The frame itself is decoded off the main actor and lands a moment later: the last of four greys.
        let last = 255 * 4 / 5
        await Self.waitUntil { Self.grey(player.frame).map { abs($0 - last) < 8 } == true }
        #expect(Self.grey(player.frame).map { abs($0 - last) < 8 } == true)

        player.toggle()
        #expect(player.isPlaying)
        player.stop()
        #expect(!player.isPlaying)
        #expect(player.frame == nil)
        #expect(player.duration == 0)
    }

    @Test func aSingleFrameGIFJustShows() async throws {
        let url = try Self.makeGIF(frames: 1, delay: 0.1)
        defer { try? FileManager.default.removeItem(at: url) }
        let player = GalleryGIFPlayer()
        player.load(url)
        await Self.waitUntil { player.frame != nil }
        #expect(player.frame != nil)
        #expect(!player.isPlaying)
    }

    @Test func aFileThatIsNotAnImageFails() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "gallery-\(UUID().uuidString).gif")
        try Data("nope".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let player = GalleryGIFPlayer()
        player.load(url)
        await Self.waitUntil { player.failed }
        #expect(player.failed)
    }
}
