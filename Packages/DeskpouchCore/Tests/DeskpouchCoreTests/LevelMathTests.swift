import Foundation
import Testing
@testable import DeskpouchCore

struct LevelMathTests {
    @Test func silenceIsZero() {
        #expect(LevelMath.rms([Float]()) == 0)
        #expect(LevelMath.normalized(rms: 0) == 0)
        #expect(LevelMath.normalized(rms: 0.001) == 0) // -60 dB, under the floor
    }

    @Test func fullScaleSaturates() {
        #expect(LevelMath.rms([1, -1, 1, -1]) == 1)
        #expect(LevelMath.normalized(rms: 1) == 1)
    }

    @Test func midRangeIsLinearInDecibels() {
        // -30 dB sits halfway between the -50 floor and the -10 ceiling.
        let rms = Float(pow(10.0, -30.0 / 20.0))
        #expect(abs(LevelMath.normalized(rms: rms) - 0.5) < 0.001)
    }

    @Test func rmsOfConstantSignal() {
        #expect(abs(LevelMath.rms([0.5, 0.5, 0.5]) - 0.5) < 1e-6)
    }
}
