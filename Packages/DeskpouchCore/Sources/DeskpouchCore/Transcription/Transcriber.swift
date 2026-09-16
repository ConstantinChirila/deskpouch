import Foundation

public struct Transcript: Sendable, Equatable {
    public let text: String
    /// Wall time the model took.
    public let processingTime: TimeInterval

    public init(text: String, processingTime: TimeInterval) {
        self.text = text
        self.processingTime = processingTime
    }
}

/// Speech to text. Parakeet is first; WhisperKit or a cloud provider can slot in later.
public protocol Transcriber: AnyObject, Sendable {
    /// Short label for the pill, e.g. "Parakeet v3".
    var displayName: String { get }
    /// Download and load models. Called at launch to warm up and again before the first transcription.
    /// `status` receives short human-readable progress lines.
    func prepare(status: @escaping @Sendable (String) -> Void) async throws
    /// ISO 639-1 codes this engine accepts as a language hint, e.g. ["en", "de"]. Empty when hints are unsupported.
    var supportedLanguages: [String] { get }
    /// `samples` are 16 kHz mono Float32. `language` is an ISO 639-1 hint or nil for auto.
    func transcribe(samples: [Float], language: String?) async throws -> Transcript
    /// Free the loaded models. The next `prepare` loads them again.
    func unload() async
}

public extension Transcriber {
    func unload() async {}
}
