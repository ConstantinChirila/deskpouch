import Foundation

/// What the Trim editor keeps of a recording: the in and out points and the playhead, in seconds. Pure, so the
/// clamping rules are unit tested; the player and the exporters read it.
struct TrimModel: Equatable, Sendable {
    /// The kept part is never shorter than this (or than the recording, when that is shorter still).
    static let minimumLength: TimeInterval = 0.5
    /// Handle drags land on tenths of a second. I and O take the playhead as it is.
    static let snap: TimeInterval = 0.1

    let duration: TimeInterval
    let frameRate: Double
    private(set) var start: TimeInterval = 0
    private(set) var end: TimeInterval
    private(set) var playhead: TimeInterval = 0

    /// `frameRate` is the track's nominal rate; anything unusable falls back to 60, the recorder's default.
    init(duration: TimeInterval, frameRate: Double) {
        self.duration = max(0, duration)
        self.frameRate = frameRate.isFinite && frameRate >= 1 ? frameRate : 60
        end = self.duration
    }

    var selectedDuration: TimeInterval { end - start }
    var isTrimmed: Bool { start > 0 || end < duration }
    var frameDuration: TimeInterval { 1 / frameRate }
    private var minimum: TimeInterval { min(Self.minimumLength, duration) }

    /// Moves the in point. It stops short of the out point instead of pushing or crossing it.
    mutating func setStart(_ time: TimeInterval, snapping: Bool = true) {
        start = min(max(0, snapping ? snapped(time) : time), end - minimum)
        start = max(0, start)
        playhead = min(max(playhead, start), end)
    }

    /// Moves the out point. It stops short of the in point instead of pushing or crossing it.
    mutating func setEnd(_ time: TimeInterval, snapping: Bool = true) {
        end = max(min(duration, snapping ? snapped(time) : time), start + minimum)
        end = min(duration, end)
        playhead = min(max(playhead, start), end)
    }

    /// Anywhere in the recording, not only inside the kept part: what is about to be cut can still be looked at.
    mutating func seek(to time: TimeInterval) {
        playhead = min(max(0, time), duration)
    }

    /// Arrow keys: whole frames, from the frame the playhead is on.
    mutating func step(frames: Int) {
        let frame = (playhead * frameRate).rounded() + Double(frames)
        seek(to: frame / frameRate)
    }

    /// I: the kept part starts at the playhead.
    mutating func markIn() {
        setStart(playhead, snapping: false)
    }

    /// O: the kept part ends at the playhead.
    mutating func markOut() {
        setEnd(playhead, snapping: false)
    }

    /// Tenths of a second, except that the very end of the recording stays reachable.
    private func snapped(_ time: TimeInterval) -> TimeInterval {
        if time >= duration - Self.snap / 2 { return duration }
        return (time / Self.snap).rounded() * Self.snap
    }

    /// "0:04.2".
    static func label(_ time: TimeInterval) -> String {
        let tenths = Int((max(0, time) * 10).rounded())
        return "\(tenths / 600):" + String(format: "%02d.%d", (tenths / 10) % 60, tenths % 10)
    }
}
