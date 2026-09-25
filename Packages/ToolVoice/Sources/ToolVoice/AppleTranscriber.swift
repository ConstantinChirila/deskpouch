import AVFoundation
import DeskpouchCore
import Foundation
import Speech
import Synchronization
import os

private let log = Logger(subsystem: "com.constantinchirila.deskpouch", category: "apple-speech")

public enum AppleTranscriberError: LocalizedError {
    case denied
    case unavailable(String)
    case needsLanguageDownload(String)
    case dictationOff

    public var errorDescription: String? {
        switch self {
        case .denied: "Speech Recognition access is off for Deskpouch"
        case .unavailable(let language): "Apple Speech has no recogniser for \(language)"
        case .needsLanguageDownload(let language): "Enable Dictation for \(language) in System Settings › Keyboard to get on-device recognition"
        case .dictationOff: "Turn on Dictation in System Settings › Keyboard to use Apple Speech"
        }
    }
}

/// macOS's own speech recognition (the Speech framework), on-device only. Nothing to download; accuracy and
/// punctuation trail Parakeet, which is the trade for the disk space.
public final class AppleTranscriber: Transcriber, @unchecked Sendable {
    public let displayName = "Apple Speech"

    private let onDeviceLocales = Mutex<(locales: [Locale], built: Date)?>(nil)

    /// An empty locale list is built again after this long. Building asks for a recogniser per locale, and the
    /// panel reads the list on the main actor, so not on every read.
    private static let emptyListLifetime: TimeInterval = 10

    public init() {}

    /// ISO 639-1 codes with an on-device recogniser, once per language, the user's locale first.
    public var supportedLanguages: [String] {
        var seen: Set<String> = []
        return locales().compactMap { locale in
            guard let code = locale.language.languageCode?.identifier.lowercased(), !seen.contains(code) else { return nil }
            seen.insert(code)
            return code
        }
    }

    public func prepare(status: @escaping @Sendable (String) -> Void) async throws {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            return
        case .notDetermined:
            status("Allow Speech Recognition to use Apple Speech")
            let granted = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
            }
            if !granted { throw AppleTranscriberError.denied }
        default:
            throw AppleTranscriberError.denied
        }
    }

    public func transcribe(samples: [Float], language: String?) async throws -> Transcript {
        let code = language ?? "en"
        // A list built while Dictation was off misses the language: build it again before giving up.
        guard let locale = locale(for: code) ?? locale(for: code, rebuilding: true), let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw AppleTranscriberError.unavailable(code.uppercased())
        }
        guard recognizer.supportsOnDeviceRecognition else {
            throw AppleTranscriberError.needsLanguageDownload(locale.localizedString(forLanguageCode: code) ?? code.uppercased())
        }
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: MicRecorder.sampleRate, channels: 1, interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(max(samples.count, 1))),
              let channel = buffer.floatChannelData?[0] else {
            throw AppleTranscriberError.unavailable(code.uppercased())
        }
        samples.withUnsafeBufferPointer { source in
            channel.update(from: source.baseAddress!, count: source.count)
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false
        request.addsPunctuation = true
        request.taskHint = .dictation
        request.append(buffer)
        request.endAudio()

        let started = Date()
        let outcome = Outcome()
        let text: String = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                outcome.begin(continuation)
                let task = recognizer.recognitionTask(with: request) { result, error in
                    if let error {
                        let nsError = error as NSError
                        // 1110 is "No speech detected": an empty transcript, not a failure.
                        if nsError.domain == "kAFAssistantErrorDomain", nsError.code == 1110 {
                            outcome.finish(.success(""))
                        } else if nsError.domain == "kLSRErrorDomain", nsError.code == 201 {
                            // "Siri and Dictation are disabled": the on-device recogniser only runs with Dictation on.
                            outcome.finish(.failure(AppleTranscriberError.dictationOff))
                        } else {
                            log.error("recognition failed: \(String(describing: error), privacy: .public)")
                            outcome.finish(.failure(error))
                        }
                        return
                    }
                    if let result, result.isFinal {
                        outcome.finish(.success(result.bestTranscription.formattedString))
                    }
                }
                // The outcome holds the recogniser and its task until a result arrives; nothing else does.
                outcome.hold(recognizer: recognizer, task: task)
            }
        } onCancel: {
            outcome.cancel()
        }
        return Transcript(text: text.trimmingCharacters(in: .whitespacesAndNewlines), processingTime: Date().timeIntervalSince(started))
    }

    /// Resumes the continuation once, whichever callback arrives first, and keeps the recognition alive until then.
    private final class Outcome: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<String, Error>?
        private var recognizer: SFSpeechRecognizer?
        private var task: SFSpeechRecognitionTask?
        private var cancelled = false

        func begin(_ continuation: CheckedContinuation<String, Error>) {
            lock.withLock { self.continuation = continuation }
        }

        func hold(recognizer: SFSpeechRecognizer, task: SFSpeechRecognitionTask) {
            let cancelNow = lock.withLock {
                guard continuation != nil else { return false }
                self.recognizer = recognizer
                self.task = task
                return cancelled
            }
            if cancelNow { task.cancel() }
        }

        func cancel() {
            let task = lock.withLock {
                cancelled = true
                return self.task
            }
            task?.cancel()
            finish(.failure(CancellationError()))
        }

        func finish(_ result: Result<String, Error>) {
            let continuation = lock.withLock {
                defer {
                    self.continuation = nil
                    // Break the task -> handler -> outcome cycle.
                    self.task = nil
                    self.recognizer = nil
                }
                return self.continuation
            }
            switch result {
            case .success(let text): continuation?.resume(returning: text)
            case .failure(let error): continuation?.resume(throwing: error)
            }
        }
    }

    // MARK: Locales

    /// Locales whose recogniser runs on device, the user's own locale first, then alphabetical. An empty list is
    /// only kept briefly: it means Dictation was off, and that can change while the app runs.
    private func locales(rebuilding: Bool = false) -> [Locale] {
        if !rebuilding, let cached = onDeviceLocales.withLock({ $0 }),
           !cached.locales.isEmpty || Date().timeIntervalSince(cached.built) < Self.emptyListLifetime {
            return cached.locales
        }
        let current = Locale.current
        let all = SFSpeechRecognizer.supportedLocales()
            .filter { SFSpeechRecognizer(locale: $0)?.supportsOnDeviceRecognition == true }
            .sorted { a, b in
                if a.identifier == current.identifier { return true }
                if b.identifier == current.identifier { return false }
                return a.identifier < b.identifier
            }
        onDeviceLocales.withLock { $0 = (all, Date()) }
        return all
    }

    private func locale(for code: String, rebuilding: Bool = false) -> Locale? {
        locales(rebuilding: rebuilding).first { $0.language.languageCode?.identifier.lowercased() == code.lowercased() }
    }
}
