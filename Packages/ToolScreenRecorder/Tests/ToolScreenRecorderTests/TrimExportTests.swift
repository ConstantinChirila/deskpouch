import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import ToolScreenRecorder

struct TrimExportTests {
    /// An H.264 mp4 of `seconds` at 30 fps whose every frame is a different grey, so no two frames merge.
    static func makeVideo(seconds: Double, size: CGSize) async throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "trim-\(UUID().uuidString).mp4")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height),
        ])
        writer.add(input)
        #expect(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        let count = Int(seconds * 30)
        for frame in 0..<count {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, try #require(adaptor.pixelBufferPool), &buffer)
            let pixels = try #require(buffer)
            CVPixelBufferLockBaseAddress(pixels, [])
            memset(CVPixelBufferGetBaseAddress(pixels), Int32(grey(frame: frame, of: count)), CVPixelBufferGetDataSize(pixels))
            CVPixelBufferUnlockBaseAddress(pixels, [])
            #expect(adaptor.append(pixels, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 30)))
        }
        input.markAsFinished()
        writer.endSession(atSourceTime: CMTime(value: CMTimeValue(count), timescale: 30))
        await writer.finishWriting()
        #expect(writer.status == .completed)
        return url
    }

    /// The grey level `makeVideo` gives a frame.
    static func grey(frame: Int, of count: Int) -> Int {
        20 + frame * 200 / max(1, count)
    }

    /// Red of the top-left pixel; the frames are flat grey.
    static func grey(of image: CGImage) throws -> Int {
        var pixel = [UInt8](repeating: 0, count: 4)
        try pixel.withUnsafeMutableBytes { raw in
            let context = try #require(CGContext(
                data: raw.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(image, in: CGRect(x: 0, y: -(image.height - 1), width: image.width, height: image.height))
        }
        return Int(pixel[0])
    }

    /// Grey of the frame on screen at `seconds`.
    static func grey(of video: URL, at seconds: Double) async throws -> Int {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: video))
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        return try grey(of: try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image)
    }

    @Test func gifHasTwelveFramesASecondAndIsCappedInWidth() async throws {
        let video = try await Self.makeVideo(seconds: 1, size: CGSize(width: 1280, height: 720))
        let gif = FileManager.default.temporaryDirectory.appending(path: "trim-\(UUID().uuidString).gif")
        defer { [video, gif].forEach { try? FileManager.default.removeItem(at: $0) } }

        let output = try await GIFExporter.export(video, range: 0...1, to: gif)
        #expect(output.ticks == 12)
        #expect(output.pixelSize == CGSize(width: 960, height: 540))

        let source = try #require(CGImageSourceCreateWithURL(gif as CFURL, nil))
        #expect(CGImageSourceGetCount(source) == 12)
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(image.width == 960)
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let delay = (properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any])?[kCGImagePropertyGIFUnclampedDelayTime] as? Double
        #expect(abs((delay ?? 0) - 1.0 / 12) < 0.011)
    }

    @Test func gifOfAPartCoversOnlyThatPart() async throws {
        let video = try await Self.makeVideo(seconds: 2, size: CGSize(width: 320, height: 180))
        let gif = FileManager.default.temporaryDirectory.appending(path: "trim-\(UUID().uuidString).gif")
        defer { [video, gif].forEach { try? FileManager.default.removeItem(at: $0) } }

        let output = try await GIFExporter.export(video, range: 0.5...1.0, to: gif)
        #expect(output.ticks == 6)
        #expect(output.pixelSize == CGSize(width: 320, height: 180))

        let source = try #require(CGImageSourceCreateWithURL(gif as CFURL, nil))
        #expect(CGImageSourceGetCount(source) == 6)
        // Against the video's own frames, decoded the same way: the codec and the GIF palette shift a grey a
        // little, the wrong part of the recording shifts it a lot (the video runs from grey 20 to about 217).
        let first = try Self.grey(of: try #require(CGImageSourceCreateImageAtIndex(source, 0, nil)))
        let last = try Self.grey(of: try #require(CGImageSourceCreateImageAtIndex(source, 5, nil)))
        #expect(abs(first - (try await Self.grey(of: video, at: 0.5))) <= 6)
        // The last tick is at 0.5 + 5/12 s.
        #expect(abs(last - (try await Self.grey(of: video, at: 0.5 + 5.0 / 12))) <= 6)
        #expect(last - first > 25)
    }

    @Test func aCancelledGIFLeavesNoFile() async throws {
        let video = try await Self.makeVideo(seconds: 2, size: CGSize(width: 320, height: 180))
        let gif = FileManager.default.temporaryDirectory.appending(path: "trim-\(UUID().uuidString).gif")
        defer { [video, gif].forEach { try? FileManager.default.removeItem(at: $0) } }

        let task = Task { try await GIFExporter.export(video, range: 0...2, to: gif) }
        task.cancel()
        await #expect(throws: (any Error).self) { try await task.value }
        #expect(!FileManager.default.fileExists(atPath: gif.path))
    }

    @Test func mp4TrimKeepsTheRange() async throws {
        let video = try await Self.makeVideo(seconds: 2, size: CGSize(width: 320, height: 180))
        let trimmed = FileManager.default.temporaryDirectory.appending(path: "trim-\(UUID().uuidString).mp4")
        defer { [video, trimmed].forEach { try? FileManager.default.removeItem(at: $0) } }

        try await MP4Exporter.export(video, range: 0.5...1.5, to: trimmed)
        let duration = try await AVURLAsset(url: trimmed).load(.duration).seconds
        #expect(abs(duration - 1) < 0.1)
    }

    @Test func outputSizeNeverUpscales() {
        #expect(GIFExporter.outputSize(for: CGSize(width: 640, height: 400)) == CGSize(width: 640, height: 400))
        #expect(GIFExporter.outputSize(for: CGSize(width: 2080, height: 1520)) == CGSize(width: 960, height: 702))
    }
}
