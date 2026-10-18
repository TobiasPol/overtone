import Foundation

/// Turns a noisy stream of proposals into rare, well-timed switches. A new value has to persist for
/// `holdTime` at the very first decision and for `gapWindow` seconds after a gap in the audio (a
/// likely track change, so a misleading intro can still be corrected); at any other time it has to
/// persist for `forceTime` (gapless albums, DJ mixes).
///
/// Tuned by replaying classifier output for 33 tracks (about 2 hours) as a playlist: this policy
/// kept an acceptable preset 84% of the time with 40 switches, against 77% and 44 switches when
/// every decision after the first needed `forceTime` and the fallback could override any style.
struct DetectionStabilizer<Value: Equatable> {
    var holdTime: TimeInterval
    var forceTime: TimeInterval
    /// How long after a gap decisions only need `holdTime`.
    var gapWindow: TimeInterval
    /// "No clear answer": it may replace the previous track's value (the first switch after a gap,
    /// or the first decision ever) but never a decision already made for the current track, so a
    /// quiet passage can't knock out a style the track clearly had.
    var fallback: Value?
    private(set) var current: Value?
    private var candidate: Value?
    private var candidateSince: TimeInterval = 0
    private var lastGap: TimeInterval?
    private var decidedSinceGap = false

    /// Explicit, because the private state makes the memberwise initializer fileprivate before Swift 6.4.
    init(holdTime: TimeInterval = 6, forceTime: TimeInterval = 45, gapWindow: TimeInterval = 45, fallback: Value? = nil) {
        self.holdTime = holdTime
        self.forceTime = forceTime
        self.gapWindow = gapWindow
        self.fallback = fallback
    }

    mutating func noteGap(at time: TimeInterval) {
        lastGap = time
        candidate = nil
        decidedSinceGap = false
    }

    mutating func reset() {
        self = DetectionStabilizer(holdTime: holdTime, forceTime: forceTime, gapWindow: gapWindow, fallback: fallback)
    }

    /// Feeds the latest proposal; returns the value to switch to, or nil to stay put.
    mutating func update(_ proposal: Value?, at time: TimeInterval) -> Value? {
        guard let proposal, proposal != current, !(proposal == fallback && current != nil && decidedSinceGap) else {
            candidate = nil
            return nil
        }
        if candidate != proposal {
            candidate = proposal
            candidateSince = time
        }
        let held = time - candidateSince
        let nearGap = lastGap.map { time - $0 <= gapWindow } ?? false
        guard held >= (current == nil || nearGap ? holdTime : forceTime) else { return nil }
        current = proposal
        candidate = nil
        decidedSinceGap = true
        return proposal
    }
}

/// Reports a gap once the audio has stayed below `thresholdDB` for `minimumGap` seconds.
struct SilenceGate {
    var thresholdDB: Float
    var minimumGap: TimeInterval
    private var silentFor: TimeInterval = 0
    private var reported = false

    init(thresholdDB: Float = -55, minimumGap: TimeInterval = 0.8) {
        self.thresholdDB = thresholdDB
        self.minimumGap = minimumGap
    }

    /// Feeds one block's RMS level (linear); returns true exactly once per gap.
    mutating func feed(rms: Float, duration: TimeInterval) -> Bool {
        guard 20 * log10(max(rms, 1e-9)) < thresholdDB else {
            silentFor = 0
            reported = false
            return false
        }
        silentFor += duration
        guard silentFor >= minimumGap, !reported else { return false }
        reported = true
        return true
    }
}
