import Foundation
import Observation

/// A decision about what is playing and which preset suits it.
struct AutoDetection: Equatable, Sendable {
    enum Source: Equatable, Sendable {
        case sound
        case musicApp(genre: String)
    }

    var label: String
    /// Built-in Advanced preset to apply; nil means "keep the user's own equalizer".
    var presetName: String?
    var source: Source

    static func sound(_ category: SoundCategory) -> AutoDetection {
        AutoDetection(label: category.label, presetName: category.presetName, source: .sound)
    }

    static func musicApp(genre: String, preset: String) -> AutoDetection {
        AutoDetection(label: preset, presetName: preset, source: .musicApp(genre: genre))
    }

    var detail: String {
        switch source {
        case .sound: return presetName == nil ? "No clear style, using your EQ" : "Detected from the sound"
        case let .musicApp(genre): return "Music genre “\(genre)”"
        }
    }
}

/// Combines the three detection layers: Music.app's genre tag when Music is the only app
/// playing, otherwise the sound classifier (speech vs music, then style from instruments),
/// voted over time and switched only at gaps so presets don't jump around mid-song.
@MainActor @Observable
final class MusicTypeDetector {
    private(set) var detection: AutoDetection?
    private(set) var isRunning = false
    @ObservationIgnored var onDetection: ((AutoDetection) -> Void)?
    @ObservationIgnored var useMusicApp = true {
        didSet { if useMusicApp != oldValue { evaluateMusicApp() } }
    }

    @ObservationIgnored private var classifier: SoundClassifier?
    @ObservationIgnored private let music = MusicAppMonitor()
    @ObservationIgnored private var voter = MusicTypeVoter()
    @ObservationIgnored private var stabilizer = DetectionStabilizer<SoundCategory>(fallback: .music)
    @ObservationIgnored private var musicAppInCharge = false
    @ObservationIgnored private var musicIsSoleSource = false
    @ObservationIgnored private var lastSourceCheck = -TimeInterval.infinity

    init(dsp: DSPCore) {
        classifier = SoundClassifier(dsp: dsp) { [weak self] event in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.handle(event) } }
        }
        music.onChange = { [weak self] _ in
            self?.lastSourceCheck = -.infinity
            self?.refreshSoleSource()
            self?.evaluateMusicApp()
        }
    }

    /// Starts (or restarts, after a sample rate change) listening. `speed` > 1 is for offline
    /// analysis that feeds audio faster than real time.
    func start(sampleRate: Double, speed: Double = 1) {
        isRunning = true
        resetVoting()
        classifier?.start(sampleRate: sampleRate, speed: speed)
        music.start()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        classifier?.stop()
        music.stop()
        resetVoting()
        musicAppInCharge = false
        musicIsSoleSource = false
        detection = nil
    }

    /// Screenshot support (`--snapshot`): shows a fixed detection without listening.
    func showSnapshot(_ detection: AutoDetection) {
        self.detection = detection
    }

    private func handle(_ event: SoundClassifier.Event) {
        guard isRunning else { return }
        switch event {
        case let .gap(time):
            voter.reset()
            stabilizer.noteGap(at: time)
        case let .window(scores, time):
            refreshSoleSource()
            guard !evaluateMusicApp() else { return }
            voter.add(ClassificationWindow(time: time, scores: scores))
            if let category = stabilizer.update(voter.proposal, at: time) { emit(.sound(category)) }
        }
    }

    /// Lets Music.app's genre decide while it applies; returns whether it does.
    @discardableResult
    private func evaluateMusicApp() -> Bool {
        guard isRunning else { return false }
        guard useMusicApp, musicIsSoleSource, let info = music.nowPlaying, info.isPlaying,
              let genre = info.genre, let preset = GenreMapping.presetName(forGenre: genre) else {
            if musicAppInCharge {
                musicAppInCharge = false
                resetVoting() // the classifier starts fresh instead of voting on old windows
            }
            return false
        }
        musicAppInCharge = true
        resetVoting()
        emit(.musicApp(genre: genre, preset: preset))
        return true
    }

    /// Asks Core Audio which apps are playing, at most every 3 s and only while Music plays.
    private func refreshSoleSource() {
        guard useMusicApp, music.nowPlaying?.isPlaying == true else {
            musicIsSoleSource = false
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastSourceCheck >= 3 else { return }
        lastSourceCheck = now
        musicIsSoleSource = MusicAppMonitor.isSoleAudioSource()
    }

    private func resetVoting() {
        voter.reset()
        stabilizer.reset()
    }

    private func emit(_ next: AutoDetection) {
        guard next != detection else { return }
        detection = next
        Log.detection.info("Detected \(next.label, privacy: .public) (\(next.detail, privacy: .public))")
        onDetection?(next)
    }
}
