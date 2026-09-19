import AVFoundation
import Foundation

enum TrimExportError: Error {
    case noVideoTrack
    case cannotExport
    case cannotRead(Error?)
    case cannotWrite
}

/// Cuts a recording to a time range without re-encoding: the samples are copied as they are, so it takes
/// seconds and loses nothing.
enum MP4Exporter {
    static func export(_ source: URL, range: ClosedRange<TimeInterval>, to destination: URL) async throws {
        let asset = AVURLAsset(url: source)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            throw TrimExportError.cannotExport
        }
        session.timeRange = CMTimeRange(range)
        try await session.export(to: destination, as: .mp4)
    }
}

extension CMTimeRange {
    /// Seconds to media time at a timescale fine enough for any frame rate the recorder writes.
    init(_ range: ClosedRange<TimeInterval>) {
        self.init(
            start: CMTime(seconds: range.lowerBound, preferredTimescale: 600_00),
            end: CMTime(seconds: range.upperBound, preferredTimescale: 600_00)
        )
    }
}
