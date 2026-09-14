import Foundation
import Observation

/// Observable wrapper around `LevelHistory` for SwiftUI meters.
@MainActor
@Observable
public final class LevelMeterModel {
    private var history: LevelHistory

    public init(barCount: Int) {
        history = LevelHistory(count: barCount)
    }

    public var bars: [Float] { history.bars }
    public var current: Float { history.current }

    public func push(level: Float, dt: TimeInterval) {
        history.push(level: level, dt: dt)
    }

    public func reset() {
        history.reset()
    }
}
