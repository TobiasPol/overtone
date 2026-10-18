import Foundation

/// What the built-in sound classifier thinks is playing, reduced to the categories that have a
/// matching built-in preset. `.music` means "music, but no clear style": the user's own EQ applies.
enum SoundCategory: String, CaseIterable, Sendable {
    case speech, hipHop, rock, jazz, electronic, classical, piano, acoustic, music

    var label: String {
        switch self {
        case .speech: return "Speech"
        case .hipHop: return "Hip-Hop"
        case .rock: return "Rock"
        case .jazz: return "Jazz"
        case .electronic: return "Electronic"
        case .classical: return "Classical"
        case .piano: return "Piano"
        case .acoustic: return "Acoustic"
        case .music: return "Music"
        }
    }

    /// Built-in Advanced preset for this category; nil keeps the user's own equalizer.
    var presetName: String? {
        switch self {
        case .speech: return "Spoken Word"
        case .music: return nil
        default: return label
        }
    }

    /// Classifier labels the rules look at (Apple's `SNClassifierIdentifier.version1` names).
    static let labels: Set<String> = [
        "music", "speech", "singing", "rapping", "choir_singing", "orchestra", "bowed_string_instrument",
        "piano", "synthesizer", "electric_guitar", "acoustic_guitar", "drum_kit", "bass_drum", "snare_drum", "hi_hat",
        "saxophone", "brass_instrument",
    ]

    /// Maps mean label confidences (0…1) over a listening window to a category, or nil when the
    /// window holds neither clear speech nor clear music (silence, noise, sound effects).
    ///
    /// Thresholds come from about 40 tracks: the soundtracks macOS ships for Photos Memories plus
    /// Creative Commons netlabel releases. Rap scores rapping 0.45–0.77 (its speech never beats music);
    /// rock and metal electric guitar 0.32–0.59 with drum kit 0.29–0.79 and almost no brass (≤ 0.11; a
    /// soul-jazz intro with the same guitar and drums had brass 0.24); sax-led and big-band jazz
    /// saxophone ≥ 0.41 or brass 0.5 over a drum kit; EDM synthesizer 0.5–0.8 well above its piano (its
    /// beat barely registers as drums); orchestral tracks orchestra ≥ 0.7 or bowed strings ≥ 0.5;
    /// bluegrass acoustic guitar 0.73; solo piano 0.70. Soul, chillhop, electropop and quiet jazz have no
    /// distinctive label and fall back to `.music`. Sung R&B partly scores as rapping and lands on
    /// Hip-Hop, whose preset is close to R&B's.
    static func categorize(_ s: [String: Double]) -> SoundCategory? {
        func v(_ label: String) -> Double { s[label] ?? 0 }
        let music = v("music"), speech = v("speech")
        if speech >= 0.5 && speech > music { return .speech }
        guard music >= 0.4 else { return nil }
        let drumKit = v("drum_kit")
        let beat = max(drumKit, v("bass_drum"), v("snare_drum"), v("hi_hat"))
        if v("rapping") >= 0.3 { return .hipHop }
        let horns = v("brass_instrument")
        if v("electric_guitar") >= 0.3 && drumKit >= 0.25 && horns < 0.2 { return .rock }
        if v("saxophone") >= 0.35 || (horns >= 0.4 && drumKit >= 0.3) { return .jazz }
        let synth = v("synthesizer"), piano = v("piano")
        if synth >= 0.35 && (beat >= 0.15 || (synth >= 0.45 && synth >= piano + 0.15)) { return .electronic }
        let orchestral = v("orchestra") >= 0.4 || v("choir_singing") >= 0.4 || v("bowed_string_instrument") >= 0.45
        if drumKit < 0.2 && orchestral { return .classical }
        if piano >= 0.45 && drumKit < 0.15 && v("singing") < 0.3 { return .piano }
        if v("acoustic_guitar") >= 0.4 && drumKit < 0.2 { return .acoustic }
        return .music
    }
}

/// One classifier result: label confidences for a ~3 s slice of audio.
struct ClassificationWindow: Sendable {
    var time: TimeInterval
    var scores: [String: Double]

    /// Windows with neither music nor speech (gaps, near silence) carry no vote.
    var hasContent: Bool {
        max(scores["music"] ?? 0, scores["speech"] ?? 0) >= 0.2
    }
}

/// Averages classifier windows over a sliding span so one odd window can't flip the result.
struct MusicTypeVoter {
    var span: TimeInterval
    var minimumWindows: Int
    private(set) var windows: [ClassificationWindow] = []

    /// Explicit, because `private(set)` makes the memberwise initializer fileprivate before Swift 6.4.
    init(span: TimeInterval = 15, minimumWindows: Int = 4) {
        self.span = span
        self.minimumWindows = minimumWindows
    }

    /// Every window ages out old votes, even one without content, so a stretch of noise or sound
    /// effects can't keep an outdated proposal alive.
    mutating func add(_ window: ClassificationWindow) {
        windows.removeAll { window.time - $0.time > span }
        if window.hasContent { windows.append(window) }
    }

    mutating func reset() {
        windows.removeAll()
    }

    var means: [String: Double] {
        guard !windows.isEmpty else { return [:] }
        var sums: [String: Double] = [:]
        for window in windows {
            for (label, score) in window.scores {
                sums[label, default: 0] += score
            }
        }
        return sums.mapValues { $0 / Double(windows.count) }
    }

    /// The category the recent windows agree on, once there are enough of them.
    var proposal: SoundCategory? {
        windows.count >= minimumWindows ? SoundCategory.categorize(means) : nil
    }
}
