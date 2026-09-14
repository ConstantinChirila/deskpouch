import Foundation

/// Placeholder level source until the voice tool feeds real microphone levels (milestone 2).
/// Produces a speech-like envelope: bursts of energy with quiet gaps.
struct SimulatedLevelSource {
    private var phase: Double = 0
    private var envelope: Float = 0
    private var target: Float = 0
    private var untilNextTarget = 0

    mutating func next() -> Float {
        if untilNextTarget <= 0 {
            target = Bool.random() ? Float.random(in: 0.35...1) : Float.random(in: 0...0.15)
            untilNextTarget = Int.random(in: 3...12)
        }
        untilNextTarget -= 1
        envelope += (target - envelope) * 0.35
        let jitter = Float.random(in: -0.12...0.12)
        return min(max(envelope + jitter, 0), 1)
    }
}
