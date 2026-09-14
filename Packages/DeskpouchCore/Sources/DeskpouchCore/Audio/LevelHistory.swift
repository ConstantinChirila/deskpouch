import Foundation

/// Rolling window of smoothed audio levels for a bar meter.
/// New samples enter on the right; the displayed level decays with an 80 ms time constant.
public struct LevelHistory: Sendable, Equatable {
    public private(set) var bars: [Float]
    public let decay: TimeInterval
    private var smoothed: Float = 0

    public init(count: Int, decay: TimeInterval = 0.08) {
        precondition(count > 0, "LevelHistory needs at least one bar")
        bars = Array(repeating: 0, count: count)
        self.decay = decay
    }

    /// The level currently shown by the newest bar.
    public var current: Float { smoothed }

    /// Feed one raw level (0...1) after `dt` seconds since the previous push.
    public mutating func push(level: Float, dt: TimeInterval) {
        let clamped = min(max(level, 0), 1)
        let factor = dt <= 0 ? Float(1) : Float(exp(-dt / decay))
        smoothed = max(clamped, smoothed * factor)
        bars.removeFirst()
        bars.append(smoothed)
    }

    public mutating func reset() {
        smoothed = 0
        bars = Array(repeating: 0, count: bars.count)
    }
}
