import AVFoundation

/// Reads a 16 kHz mono Float32 file (what `say --data-format=LEF32@16000` writes). Demo use only.
enum WavLoader {
    static func samples16kMono(_ url: URL) -> [Float]? {
        guard let file = try? AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false) else { return nil }
        let format = file.processingFormat
        guard format.sampleRate == 16_000, format.channelCount == 1,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length)) else { return nil }
        do { try file.read(into: buffer) } catch { return nil }
        guard let data = buffer.floatChannelData?[0] else { return nil }
        return Array(UnsafeBufferPointer(start: data, count: Int(buffer.frameLength)))
    }
}
