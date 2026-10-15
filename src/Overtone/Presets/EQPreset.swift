import Foundation

/// A saved equalizer configuration for one EQ mode.
struct EQPreset: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var name: String
    var mode: EQMode
    var basic: BasicEQ?
    var advanced: AdvancedEQ?
    var expert: ExpertEQ?

    /// Captures the active mode's settings from `equalizer`.
    init(name: String, from equalizer: EqualizerSettings) {
        self.name = name
        mode = equalizer.mode
        switch equalizer.mode {
        case .basic: basic = equalizer.basic
        case .advanced: advanced = equalizer.advanced
        case .expert: expert = equalizer.expert
        }
    }

    init(name: String, basic: BasicEQ) {
        self.name = name
        mode = .basic
        self.basic = basic
    }

    init(name: String, advanced gains: [Double], preamp: Double = 0) {
        self.name = name
        mode = .advanced
        advanced = AdvancedEQ(gains: gains, preamp: preamp)
    }

    init(name: String, expert: ExpertEQ) {
        self.name = name
        mode = .expert
        self.expert = expert
    }

    /// Writes this preset into `equalizer`, switching to its mode.
    func apply(to equalizer: inout EqualizerSettings) {
        equalizer.mode = mode
        switch mode {
        case .basic: if let basic { equalizer.basic = basic }
        case .advanced: if let advanced { equalizer.advanced = advanced }
        case .expert: if let expert { equalizer.expert = expert }
        }
        equalizer.selectedPreset = name
    }

    /// Whether `equalizer` currently matches this preset exactly.
    func matches(_ equalizer: EqualizerSettings) -> Bool {
        guard equalizer.mode == mode else { return false }
        switch mode {
        case .basic: return basic == equalizer.basic
        case .advanced: return advanced == equalizer.advanced
        case .expert: return expert?.bands.map(\.withoutID) == equalizer.expert.bands.map(\.withoutID)
            && expert?.preamp == equalizer.expert.preamp
        }
    }
}

extension EQBand {
    /// Band with a fixed identity so comparisons ignore the random UUID.
    var withoutID: EQBand {
        var copy = self
        copy.id = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
        return copy
    }
}
