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

/// What `ScreenRecorder.stop()` hands back. `problem` is nil for a recording that was written and finalised in full.
struct FinishedRecording {
    enum Problem {
        /// `SCRecordingOutput` failed while recording (disk full, encoder error): the file ends there at best.
        case outputFailed(Error)
        /// The file was not reported finalised in time: it may be incomplete.
        case notFinalised
    }

    let url: URL
    let duration: TimeInterval
    let problem: Problem?
}

/// One ScreenCaptureKit stream writing straight to an mp4 through `SCRecordingOutput`.
/// Owned by the main actor; the delegate hops back to it for every callback.
@MainActor
final class ScreenRecorder {
    private var stream: SCStream?
    private var output: SCRecordingOutput?
    private var delegate: RecorderDelegate?
    private var finished = false
    private var outputFailure: Error?
    private var finaliseTimedOut = false
    private var finishWaiters: [CheckedContinuation<Void, Never>] = []

    private(set) var startedAt: Date?
    private(set) var outputURL: URL?
    var isRecording: Bool { stream != nil }

    /// The stream ended on its own (window closed, display unplugged, permission revoked). The file may still be usable.
    var onStreamStopped: (@MainActor (Error) -> Void)?
    /// The file stopped being written while the stream runs on. Nothing recorded after this is kept.
    var onOutputFailed: (@MainActor (Error) -> Void)?
    /// The output failed, possibly before `start` returned (when nobody was listening to `onOutputFailed` yet).
    var hasFailed: Bool { outputFailure != nil }

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
                guard let self else { return }
                outputFailure = error
                markFinished()
                onOutputFailed?(error)
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

        // Reset before the capture starts: a failure reported while `startCapture` is still returning must not
        // be wiped afterwards.
        finished = false
        outputFailure = nil
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            stream.startCapture { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }

        self.stream = stream
        self.output = output
        self.delegate = delegate
        self.outputURL = outputURL
        startedAt = Date()
        log.info("recording started: \(config.width)x\(config.height) @\(settings.frameRate) audio=\(settings.systemAudio) mic=\(microphone)")
    }

    /// Stops the stream and waits for the file to be finalised. A failed or unfinalised file comes back with its
    /// `problem` set; the caller decides what it is still worth.
    func stop() async throws -> FinishedRecording {
        guard let stream, let output, let outputURL else { throw RecorderError(message: "Not recording") }
        let duration = recordedDuration ?? startedAt.map { Date().timeIntervalSince($0) } ?? 0
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            stream.stopCapture { error in
                if let error { log.error("stopCapture: \(String(describing: error), privacy: .public)") }
                continuation.resume()
            }
        }
        let finalised = await waitForFinish(of: outputURL)
        try? stream.removeRecordingOutput(output)
        self.stream = nil
        self.output = nil
        delegate = nil
        self.outputURL = nil
        startedAt = nil
        log.info("recording stopped: \(duration, format: .fixed(precision: 1))s")
        let problem: FinishedRecording.Problem? = outputFailure.map { .outputFailed($0) } ?? (finalised ? nil : .notFinalised)
        outputFailure = nil
        return FinishedRecording(url: outputURL, duration: duration, problem: problem)
    }

    private func markFinished() {
        finished = true
        let waiters = finishWaiters
        finishWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
    }

    /// Gives up once the file has stopped growing for this long.
    static let finaliseIdleLimit = 5
    /// Gives up whatever the file is doing.
    static let finaliseHardLimit = 60

    /// True when the output reported it finished. A long recording can take a while to finalise, so the wait
    /// goes on for as long as the file keeps growing, up to `finaliseHardLimit` seconds.
    private func waitForFinish(of file: URL) async -> Bool {
        if finished { return true }
        finaliseTimedOut = false
        let timer = Task { [weak self] in
            var lastSize = -1
            var idle = 0
            for _ in 0..<Self.finaliseHardLimit {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                let size = ((try? FileManager.default.attributesOfItem(atPath: file.path))?[.size] as? NSNumber)?.intValue ?? 0
                idle = size == lastSize ? idle + 1 : 0
                lastSize = size
                if idle >= Self.finaliseIdleLimit { break }
            }
            guard !Task.isCancelled else { return }
            log.error("recording output did not finish in time")
            self?.finaliseTimedOut = true
            self?.markFinished()
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            finishWaiters.append(continuation)
        }
        timer.cancel()
        return !finaliseTimedOut
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
