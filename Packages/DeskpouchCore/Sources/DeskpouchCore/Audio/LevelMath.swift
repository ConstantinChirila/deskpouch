import Foundation

/// Maps audio power to the 0...1 range the meters draw.
public enum LevelMath {
    /// Quietest RMS that still shows a bar, and the RMS that pins the meter.
    public static let floorDB: Float = -50
    public static let ceilingDB: Float = -10

    public static func rms(_ samples: UnsafeBufferPointer<Float>) -> Float {
        guard !samples.isEmpty else { return 0 }
        var sum: Float = 0
        for s in samples { sum += s * s }
        return (sum / Float(samples.count)).squareRoot()
    }

    public static func rms(_ samples: [Float]) -> Float {
        samples.withUnsafeBufferPointer { rms($0) }
    }

    /// RMS in linear units to 0...1 on a dB scale between `floorDB` and `ceilingDB`.
    public static func normalized(rms: Float) -> Float {
        guard rms > 0 else { return 0 }
        let db = 20 * log10(rms)
        let t = (db - floorDB) / (ceilingDB - floorDB)
        return min(max(t, 0), 1)
    }
}
