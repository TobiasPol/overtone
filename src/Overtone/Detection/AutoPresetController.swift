import Foundation
import Observation

/// Auto mode: applies the built-in preset that suits what is playing. The user's own equalizer
/// is parked in `AppState.manualEqualizer` (which is what gets saved) and comes back when auto
/// mode turns off or hears music without a clear style. Editing the EQ by hand pauses auto mode
/// until the detector reports something new.
@MainActor @Observable
final class AutoPresetController {
    private(set) var isPaused = false
    @ObservationIgnored let detector: MusicTypeDetector
    /// Seconds to fade from one graphic EQ curve to the next (0 switches instantly).
    @ObservationIgnored var glideDuration: TimeInterval = 1.5
    @ObservationIgnored var sampleRate = 48_000.0 {
        didSet { if sampleRate != oldValue && detector.isRunning { detector.start(sampleRate: sampleRate) } }
    }

    @ObservationIgnored private let state: AppState
    @ObservationIgnored private var lastApplied: EqualizerSettings?
    @ObservationIgnored private var isApplying = false
    @ObservationIgnored private var glide: Glide?
    @ObservationIgnored private var glideTimer: Timer?

    private struct Glide {
        let from: AdvancedEQ
        let target: EqualizerSettings
        let began: TimeInterval
        /// Hand the equalizer back to the user once the fade ends.
        let restoresManual: Bool
    }

    init(state: AppState, dsp: DSPCore) {
        self.state = state
        detector = MusicTypeDetector(dsp: dsp)
        detector.onDetection = { [weak self] detection in self?.apply(detection) }
    }

    var isActive: Bool { state.isEnabled && state.autoPreset.isEnabled }

    /// Starts or stops detection to match the settings; stopping restores the user's equalizer.
    func update() {
        detector.useMusicApp = state.autoPreset.useMusicAppGenre
        if isActive {
            if !detector.isRunning { detector.start(sampleRate: sampleRate) }
        } else if detector.isRunning {
            detector.stop()
            isPaused = false
            cancelGlide()
            restoreManual()
        }
    }

    func apply(_ detection: AutoDetection) {
        isPaused = false
        guard let name = detection.presetName,
              let preset = BuiltInPresets.advanced.first(where: { $0.name == name }) else {
            restoreManual()
            return
        }
        if state.manualEqualizer == nil { state.manualEqualizer = state.equalizer }
        var target = state.equalizer
        preset.apply(to: &target)
        fade(to: target, restoresManual: false)
    }

    /// Call on every DSP change. An equalizer edit auto mode didn't make means the user took over:
    /// what they hear becomes their own EQ again and auto mode waits for the next detection.
    func equalizerDidChange() {
        guard !isApplying, state.manualEqualizer != nil, let lastApplied, state.equalizer != lastApplied else { return }
        if Self.sameCurve(state.equalizer, lastApplied) {
            // Only the on/off switch or auto-gain changed: carry it over, keep auto mode going.
            state.manualEqualizer?.isEnabled = state.equalizer.isEnabled
            state.manualEqualizer?.autoGain = state.equalizer.autoGain
            self.lastApplied = state.equalizer
            return
        }
        cancelGlide()
        state.manualEqualizer = nil
        self.lastApplied = nil
        isPaused = true
    }

    /// Before the output device changes: put the user's EQ back so it is stored with the old device.
    func suspendForDeviceChange() {
        cancelGlide()
        guard let manual = state.manualEqualizer else { return }
        write(manual)
        state.manualEqualizer = nil
        lastApplied = nil
    }

    /// After the new device's profile has loaded: apply the current detection on top of it.
    func resumeAfterDeviceChange() {
        guard detector.isRunning, !isPaused, let detection = detector.detection else { return }
        apply(detection)
    }

    // MARK: - Fading

    private func restoreManual() {
        guard let manual = state.manualEqualizer else { return }
        fade(to: manual, restoresManual: true)
    }

    private func fade(to target: EqualizerSettings, restoresManual: Bool) {
        cancelGlide()
        let start = state.equalizer
        guard glideDuration > 0, start.mode == .advanced, target.mode == .advanced, start.advanced != target.advanced else {
            finish(target, restoresManual: restoresManual)
            return
        }
        glide = Glide(from: start.advanced, target: target, began: Self.now, restoresManual: restoresManual)
        glideTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.glideStep() }
        }
    }

    private func glideStep() {
        guard let glide else { return cancelGlide() }
        let t = min(1, (Self.now - glide.began) / glideDuration)
        guard t < 1 else {
            cancelGlide()
            return finish(glide.target, restoresManual: glide.restoresManual)
        }
        var frame = glide.target
        frame.advanced = Self.blend(glide.from, glide.target.advanced, t * t * (3 - 2 * t))
        write(frame)
    }

    private func finish(_ target: EqualizerSettings, restoresManual: Bool) {
        write(target)
        if restoresManual {
            state.manualEqualizer = nil
            lastApplied = nil
        }
    }

    private func cancelGlide() {
        glideTimer?.invalidate()
        glideTimer = nil
        glide = nil
    }

    private func write(_ equalizer: EqualizerSettings) {
        isApplying = true
        defer { isApplying = false }
        state.equalizer = equalizer
        lastApplied = equalizer
    }

    private static var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    /// Graphic EQ curve part way (`t` in 0…1) from `a` to `b`.
    static func blend(_ a: AdvancedEQ, _ b: AdvancedEQ, _ t: Double) -> AdvancedEQ {
        AdvancedEQ(gains: zip(a.gains, b.gains).map { $0 + ($1 - $0) * t }, preamp: a.preamp + (b.preamp - a.preamp) * t)
    }

    /// Whether two settings shape the sound the same, ignoring the on/off switch and auto-gain.
    private static func sameCurve(_ a: EqualizerSettings, _ b: EqualizerSettings) -> Bool {
        var a = a
        a.isEnabled = b.isEnabled
        a.autoGain = b.autoGain
        return a == b
    }
}
