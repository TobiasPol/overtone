import Foundation

enum EQMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case basic, advanced, expert

    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

/// Three-knob tone control: bass shelf, mid peak, treble shelf.
struct BasicEQ: Codable, Equatable, Sendable {
    var bass = 0.0
    var mid = 0.0
    var treble = 0.0

    static let range = -12.0...12.0

    var bands: [EQBand] {
        [
            EQBand(type: .lowShelf, frequency: 120, gain: bass, q: 0.7),
            EQBand(type: .peak, frequency: 1_000, gain: mid, q: 0.7),
            EQBand(type: .highShelf, frequency: 6_000, gain: treble, q: 0.7),
        ]
    }
}

/// Fixed ten-band octave graphic equalizer.
struct AdvancedEQ: Codable, Equatable, Sendable {
    var gains: [Double] = Array(repeating: 0, count: AdvancedEQ.frequencies.count)
    var preamp = 0.0

    static let frequencies: [Double] = [32, 64, 125, 250, 500, 1_000, 2_000, 4_000, 8_000, 16_000]
    static let range = -12.0...12.0
    static let q = 1.41 // one-octave bandwidth

    var bands: [EQBand] {
        zip(Self.frequencies, gains).map { EQBand(type: .peak, frequency: $0, gain: $1, q: Self.q) }
    }

    static func label(for frequency: Double) -> String {
        frequency >= 1_000 ? "\(Int(frequency / 1_000))k" : "\(Int(frequency))"
    }
}

/// Unlimited (well, 32) fully parametric bands.
struct ExpertEQ: Codable, Equatable, Sendable {
    var bands: [EQBand] = ExpertEQ.defaultBands
    var preamp = 0.0

    static let maxBands = 32
    static let defaultBands: [EQBand] = [
        EQBand(type: .lowShelf, frequency: 105, gain: 0, q: 0.7),
        EQBand(type: .peak, frequency: 400, gain: 0, q: 1),
        EQBand(type: .peak, frequency: 2_500, gain: 0, q: 1),
        EQBand(type: .highShelf, frequency: 9_000, gain: 0, q: 0.7),
    ]

    /// A sensible new band placed in the widest gap between existing bands.
    func suggestedBand() -> EQBand {
        let logs = ([20.0, 20_000] + bands.map(\.frequency)).map(log10).sorted()
        let gap = zip(logs, logs.dropFirst()).max { ($0.1 - $0.0) < ($1.1 - $1.0) }
        let centre = gap.map { pow(10, ($0.0 + $0.1) / 2) } ?? 1_000
        return EQBand(type: .peak, frequency: centre.rounded(), gain: 0, q: 1)
    }
}

struct EqualizerSettings: Codable, Equatable, Sendable {
    var isEnabled = true
    var mode: EQMode = .advanced
    var basic = BasicEQ()
    var advanced = AdvancedEQ()
    var expert = ExpertEQ()
    /// Automatically lowers the preamp so boosts never clip.
    var autoGain = false
    /// Name of the preset last applied per mode (keyed by EQMode.rawValue).
    var selectedPresets: [String: String] = [:]

    var activeBands: [EQBand] {
        switch mode {
        case .basic: return basic.bands
        case .advanced: return advanced.bands
        case .expert: return expert.bands
        }
    }

    var preampDB: Double {
        switch mode {
        case .basic: return 0
        case .advanced: return advanced.preamp
        case .expert: return expert.preamp
        }
    }

    var selectedPreset: String? {
        get { selectedPresets[mode.rawValue] }
        set { selectedPresets[mode.rawValue] = newValue }
    }
}
