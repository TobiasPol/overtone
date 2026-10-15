import OvertoneDSP

/// Biquad filter shapes available in the Expert equalizer.
enum FilterType: String, Codable, CaseIterable, Identifiable, Sendable {
    case peak, lowShelf, highShelf, lowPass, highPass, bandPass, notch, allPass

    var id: String { rawValue }

    var label: String {
        switch self {
        case .peak: return "Peak"
        case .lowShelf: return "Low Shelf"
        case .highShelf: return "High Shelf"
        case .lowPass: return "Low Pass"
        case .highPass: return "High Pass"
        case .bandPass: return "Band Pass"
        case .notch: return "Notch"
        case .allPass: return "All Pass"
        }
    }

    /// Equalizer APO / AutoEQ filter code.
    var code: String {
        switch self {
        case .peak: return "PK"
        case .lowShelf: return "LSC"
        case .highShelf: return "HSC"
        case .lowPass: return "LPQ"
        case .highPass: return "HPQ"
        case .bandPass: return "BP"
        case .notch: return "NO"
        case .allPass: return "AP"
        }
    }

    var symbolName: String {
        switch self {
        case .peak: return "waveform.path"
        case .lowShelf, .highShelf: return "chart.line.flattrend.xyaxis"
        case .lowPass, .highPass: return "line.diagonal"
        case .bandPass: return "chart.bar"
        case .notch: return "scissors"
        case .allPass: return "arrow.left.and.right"
        }
    }

    /// Whether the gain parameter affects this filter shape.
    var usesGain: Bool {
        self == .peak || self == .lowShelf || self == .highShelf
    }

    var cValue: ot_filter_type {
        switch self {
        case .peak: return OT_FILTER_PEAK
        case .lowShelf: return OT_FILTER_LOW_SHELF
        case .highShelf: return OT_FILTER_HIGH_SHELF
        case .lowPass: return OT_FILTER_LOW_PASS
        case .highPass: return OT_FILTER_HIGH_PASS
        case .bandPass: return OT_FILTER_BAND_PASS
        case .notch: return OT_FILTER_NOTCH
        case .allPass: return OT_FILTER_ALL_PASS
        }
    }
}
