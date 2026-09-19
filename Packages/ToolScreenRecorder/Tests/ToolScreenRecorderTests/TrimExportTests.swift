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
            memset(CVPixelBufferGetBaseAddress(pixels), Int32(20 + frame * 200 / max(1, count)), CVPixelBufferGetDataSize(pixels))
            CVPixelBufferUnlockBaseAddress(pixels, [])
            #expect(adaptor.append(pixels, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 30)))
        }
        input.markAsFinished()
        writer.endSession(atSourceTime: CMTime(value: CMTimeValue(count), timescale: 30))
        await writer.finishWriting()
        #expect(writer.status == .completed)
        return url
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
