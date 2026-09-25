import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import VideoToolbox

/// A time range of a recording as a looping GIF: 12 frames a second, at most 960 px wide. The colours are
/// ImageIO's own 256 per frame, which is fine for UI recordings.
enum GIFExporter {
    static let framesPerSecond: Double = 12
    static let maxWidth: CGFloat = 960
    /// Progress while frames are read. The rest is `CGImageDestinationFinalize`, which does the encoding.
    static let framesShare = 0.9

    struct Output: Sendable, Equatable {
        /// Images written. A still stretch is one image with a longer delay, so this can be below `ticks`.
        let frames: Int
        /// Twelfths of a second covered.
        let ticks: Int
        let pixelSize: CGSize
    }

    /// Output size for a video of `natural` pixels: never upscaled, never wider than `maxWidth`.
    static func outputSize(for natural: CGSize) -> CGSize {
        guard natural.width > maxWidth else { return CGSize(width: natural.width.rounded(), height: natural.height.rounded()) }
        let scale = maxWidth / natural.width
        return CGSize(width: maxWidth, height: max(1, (natural.height * scale).rounded()))
    }

    /// `progress` is called off the main actor with 0...1. A cancelled or failed export leaves no file behind.
    ///
    /// ImageIO encodes nothing until `CGImageDestinationFinalize` and holds every frame until then (about 6 MB a
    /// frame at full width, measured), so callers cap the length: see `TrimDocument.gifMaxLength`.
    @discardableResult
    static func export(
        _ source: URL, range: ClosedRange<TimeInterval>, to destination: URL,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> Output {
        let asset = AVURLAsset(url: source)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw TrimExportError.noVideoTrack }
        let (natural, transform) = try await track.load(.naturalSize, .preferredTransform)
        let size = outputSize(for: natural.applying(transform).standardizedSize)

        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = CMTimeRange(range)
        // The reader scales while decoding, so full-size frames never reach this process's memory.
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height),
        ])
        // Copies: a CGImage can keep its pixel buffer until the GIF is finalized, and those must not be the
        // decoder's pooled ones.
        output.alwaysCopiesSampleData = true
        guard reader.canAdd(output) else { throw TrimExportError.cannotRead(nil) }
        reader.add(output)
        guard reader.startReading() else { throw TrimExportError.cannotRead(reader.error) }

        guard let gif = CGImageDestinationCreateWithURL(destination as CFURL, UTType.gif.identifier as CFString, 0, nil) else {
            throw TrimExportError.cannotWrite
        }
        var finished = false
        defer {
            if !finished {
                reader.cancelReading()
                try? FileManager.default.removeItem(at: destination)
            }
        }
        CGImageDestinationSetProperties(gif, [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0],
        ] as CFDictionary)

        let length = range.upperBound - range.lowerBound
        let ticks = max(1, Int((length * framesPerSecond).rounded()))
        var nextTick = 0
        var frames = 0
        // The frame on screen until the next sample arrives; it is written once it is known how long it stays.
        var held: CVPixelBuffer?

        func write(_ buffer: CVPixelBuffer, ticks count: Int) throws {
            var image: CGImage?
            VTCreateCGImageFromCVPixelBuffer(buffer, options: nil, imageOut: &image)
            guard let image else { throw TrimExportError.cannotRead(nil) }
            let delay = Double(count) / framesPerSecond
            CGImageDestinationAddImage(gif, image, [
                kCGImagePropertyGIFDictionary: [
                    kCGImagePropertyGIFDelayTime: delay,
                    kCGImagePropertyGIFUnclampedDelayTime: delay,
                ],
            ] as CFDictionary)
            frames += 1
        }

        var reading = true
        while reading, nextTick < ticks {
            try Task.checkCancellation()
            // Samples and the temporaries of a frame go as soon as the frame is handed over.
            try autoreleasepool {
                guard let sample = output.copyNextSampleBuffer() else {
                    reading = false
                    return
                }
                guard let buffer = CMSampleBufferGetImageBuffer(sample) else { return }
                // The first frame can start a little before the range; it still belongs to tick 0.
                let time = max(0, CMSampleBufferGetPresentationTimeStamp(sample).seconds - range.lowerBound)
                // Ticks strictly before this sample still show the frame held so far.
                let upTo = min(ticks, Int((time * framesPerSecond - 1e-6).rounded(.up)))
                if let held, upTo > nextTick {
                    try write(held, ticks: upTo - nextTick)
                    progress?(Self.framesShare * Double(upTo) / Double(ticks))
                }
                nextTick = max(nextTick, upTo)
                held = buffer
            }
        }
        reader.cancelReading()
        if let held, nextTick < ticks {
            try write(held, ticks: ticks - nextTick)
        }
        guard frames > 0 else { throw TrimExportError.cannotRead(reader.error) }
        // Finalize does the encoding and cannot be stopped, so this is the last chance.
        try Task.checkCancellation()
        progress?(framesShare)
        guard CGImageDestinationFinalize(gif) else { throw TrimExportError.cannotWrite }
        finished = true
        progress?(1)
        return Output(frames: frames, ticks: ticks, pixelSize: size)
    }
}

private extension CGSize {
    /// A rotated track's transformed size comes out negative.
    var standardizedSize: CGSize { CGSize(width: abs(width), height: abs(height)) }
}
