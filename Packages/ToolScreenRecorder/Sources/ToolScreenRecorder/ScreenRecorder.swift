import AVFoundation
import DeskpouchCapture
import DeskpouchCore
import Foundation
import ScreenCaptureKit
import os

private let log = Logger(subsystem: "com.constantinchirila.deskpouch", category: "recorder")

/// What to capture. Rects are display-local points with a top-left origin, as ScreenCaptureKit wants them.
enum CaptureTarget {
    case display(SCDisplay, region: CGRect?)
    case window(SCWindow)

    /// Size of the captured area in points.
    var pointSize: CGSize {
        switch self {
        case .display(let display, let region): region?.size ?? display.frame.size
        case .window(let window): window.frame.size
        }
    }
}

struct RecorderError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// One ScreenCaptureKit stream writing straight to an mp4 through `SCRecordingOutput`.
/// Owned by the main actor; the delegate hops back to it for every callback.
@MainActor
final class ScreenRecorder {
    private var stream: SCStream?
    private var output: SCRecordingOutput?
    private var delegate: RecorderDelegate?
    private var finished = false
    private var finishWaiters: [CheckedContinuation<Void, Never>] = []

    private(set) var startedAt: Date?
    private(set) var outputURL: URL?
    var isRecording: Bool { stream != nil }

    /// The stream ended on its own (window closed, display unplugged, permission revoked). The file may still be usable.
    var onStreamStopped: (@MainActor (Error) -> Void)?

    /// What `SCRecordingOutput` has written so far, or nil before the first frame.
    var recordedDuration: TimeInterval? {
        guard let output else { return nil }
        let time = output.recordedDuration
        return time.isValid && time.isNumeric ? time.seconds : nil
    }

    func start(
        target: CaptureTarget, settings: RecorderSettings, pixelsPerPoint: CGFloat,
        excluding app: SCRunningApplication?, microphone: Bool, outputURL: URL
    ) async throws {
        guard stream == nil else { throw RecorderError(message: "Already recording") }

        let filter: SCContentFilter
        switch target {
        case .display(let display, _):
            if let app {
                filter = SCContentFilter(display: display, excludingApplications: [app], exceptingWindows: [])
            } else {
                filter = SCContentFilter(display: display, excludingWindows: [])
            }
        case .window(let window):
            filter = SCContentFilter(desktopIndependentWindow: window)
        }

        let config = SCStreamConfiguration()
        let size = CaptureGeometry.outputSize(points: target.pointSize, pixelsPerPoint: pixelsPerPoint)
        config.width = Int(size.width)
        config.height = Int(size.height)
        if case .display(_, let region?) = target {
            config.sourceRect = region
        }
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(settings.frameRate))
        config.showsCursor = settings.showsCursor
        config.queueDepth = 6
        config.capturesAudio = settings.systemAudio
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 48000
        config.channelCount = 2
        config.captureMicrophone = microphone

        let delegate = RecorderDelegate(
            onFinish: { [weak self] in self?.markFinished() },
            onFail: { [weak self] error in
                log.error("recording output failed: \(String(describing: error), privacy: .public)")
                self?.markFinished()
            },
            onStreamStop: { [weak self] error in
                log.error("stream stopped: \(String(describing: error), privacy: .public)")
                self?.onStreamStopped?(error)
            }
        )
        let stream = SCStream(filter: filter, configuration: config, delegate: delegate)

        let recording = SCRecordingOutputConfiguration()
        recording.outputURL = outputURL
        recording.videoCodecType = .h264
        recording.outputFileType = .mp4
        let output = SCRecordingOutput(configuration: recording, delegate: delegate)
        try stream.addRecordingOutput(output)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            stream.startCapture { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }

        self.stream = stream
        self.output = output
        self.delegate = delegate
        self.outputURL = outputURL
        finished = false
        startedAt = Date()
        log.info("recording started: \(config.width)x\(config.height) @\(settings.frameRate) audio=\(settings.systemAudio) mic=\(microphone)")
    }

    /// Stops the stream and waits for the file to be finalised. Returns the file and its duration.
    func stop() async throws -> (url: URL, duration: TimeInterval) {
        guard let stream, let output, let outputURL else { throw RecorderError(message: "Not recording") }
        let duration = recordedDuration ?? startedAt.map { Date().timeIntervalSince($0) } ?? 0
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            stream.stopCapture { error in
                if let error { log.error("stopCapture: \(String(describing: error), privacy: .public)") }
                continuation.resume()
            }
        }
        await waitForFinish(timeout: .seconds(5))
        try? stream.removeRecordingOutput(output)
        self.stream = nil
        self.output = nil
        delegate = nil
        self.outputURL = nil
        startedAt = nil
        log.info("recording stopped: \(duration, format: .fixed(precision: 1))s")
        return (outputURL, duration)
    }

    private func markFinished() {
        finished = true
        let waiters = finishWaiters
        finishWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
    }

    private func waitForFinish(timeout: Duration) async {
        if finished { return }
        let timer = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else { return }
            log.error("recording output did not finish in time")
            self?.markFinished()
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            finishWaiters.append(continuation)
        }
        timer.cancel()
    }
}

/// ScreenCaptureKit calls these on its own queues; every one is forwarded to the main actor.
private final class RecorderDelegate: NSObject, SCStreamDelegate, SCRecordingOutputDelegate, @unchecked Sendable {
    private let onFinish: @MainActor @Sendable () -> Void
    private let onFail: @MainActor @Sendable (Error) -> Void
    private let onStreamStop: @MainActor @Sendable (Error) -> Void

    init(
        onFinish: @escaping @MainActor @Sendable () -> Void,
        onFail: @escaping @MainActor @Sendable (Error) -> Void,
        onStreamStop: @escaping @MainActor @Sendable (Error) -> Void
    ) {
        self.onFinish = onFinish
        self.onFail = onFail
        self.onStreamStop = onStreamStop
    }

    func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) {
        log.info("recording output started")
    }

    func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        let handler = onFinish
        Task { @MainActor in handler() }
    }

    func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
        let handler = onFail
        Task { @MainActor in handler(error) }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        let handler = onStreamStop
        Task { @MainActor in handler(error) }
    }
}
