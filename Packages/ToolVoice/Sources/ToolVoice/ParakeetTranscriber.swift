import DeskpouchCore
import FluidAudio
import Foundation
import Synchronization
import os

private let log = Logger(subsystem: "com.constantinchirila.deskpouch", category: "parakeet")

/// Parakeet TDT 0.6B v3 through FluidAudio (CoreML, Neural Engine). Models download from HuggingFace on first use.
public final class ParakeetTranscriber: Transcriber, Sendable {
    public let displayName = "Parakeet v3"

    private let manager = AsrManager(config: .default)
    private let prepareTask = Mutex<Task<Void, any Error>?>(nil)
    private let statusHandlers = Mutex<[@Sendable (String) -> Void]>([])

    public init() {}

    public func prepare(status: @escaping @Sendable (String) -> Void) async throws {
        statusHandlers.withLock { $0.append(status) }
        let task = prepareTask.withLock { existing -> Task<Void, any Error> in
            if let existing { return existing }
            let task = Task { [manager, self] in
                let models = try await AsrModels.downloadAndLoad(version: .v3) { progress in
                    let percent = Int((progress.fractionCompleted * 100).rounded())
                    self.report("Downloading model · \(percent)%")
                }
                self.report("Loading model…")
                try await manager.loadModels(models)
                log.info("models loaded")
            }
            existing = task
            return task
        }
        do {
            try await task.value
        } catch {
            // Allow a retry on the next call.
            prepareTask.withLock { $0 = nil }
            statusHandlers.withLock { $0.removeAll() }
            log.error("prepare failed: \(String(describing: error), privacy: .public)")
            throw error
        }
        statusHandlers.withLock { $0.removeAll() }
    }

    public var supportedLanguages: [String] { Language.allCases.map(\.rawValue) }

    public func transcribe(samples: [Float], language: String?) async throws -> Transcript {
        try await prepare { _ in }
        var decoder = try TdtDecoderState()
        // The hint keeps the v3 decoder on one script, so unknown names stay Latin instead of drifting to Cyrillic.
        let hint = language.flatMap(Language.init(rawValue:))
        let result = try await manager.transcribe(samples, decoderState: &decoder, language: hint)
        let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        log.info("transcribed \(samples.count) samples in \(result.processingTime, format: .fixed(precision: 2))s")
        return Transcript(text: text, processingTime: result.processingTime)
    }

    private func report(_ message: String) {
        let handlers = statusHandlers.withLock { $0 }
        for handler in handlers { handler(message) }
    }
}
