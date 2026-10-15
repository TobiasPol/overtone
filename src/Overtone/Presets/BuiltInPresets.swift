import Foundation

/// Factory presets. Graphic presets follow the familiar iTunes/Music curves.
enum BuiltInPresets {
    static let flatName = "Flat"

    static let advanced: [EQPreset] = [
        .init(name: flatName, advanced: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
        .init(name: "Acoustic", advanced: [5, 5, 4, 1, 1.5, 1.5, 3.5, 4, 3.5, 2]),
        .init(name: "Bass Booster", advanced: [5.5, 4.5, 3.5, 2.5, 1.5, 0, 0, 0, 0, 0]),
        .init(name: "Bass Reducer", advanced: [-5.5, -4.5, -3.5, -2.5, -1.5, 0, 0, 0, 0, 0]),
        .init(name: "Classical", advanced: [4.5, 3.5, 3, 2.5, -1.5, -1.5, 0, 2, 3, 3.5]),
        .init(name: "Dance", advanced: [3.5, 6.5, 5, 0, 2, 3.5, 5, 4.5, 3.5, 0], preamp: -3),
        .init(name: "Deep", advanced: [5, 3.5, 1.5, 1, 3, 2.5, 1.5, -2, -3.5, -4.5]),
        .init(name: "Electronic", advanced: [4, 3.5, 1, 0, -2, 2, 1, 1, 4, 4.5]),
        .init(name: "Hip-Hop", advanced: [5, 4, 1.5, 3, -1, -1, 1.5, -0.5, 2, 3]),
        .init(name: "Jazz", advanced: [4, 3, 1.5, 2, -1.5, -1.5, 0, 1.5, 3, 3.5]),
        .init(name: "Latin", advanced: [4.5, 3, 0, 0, -1.5, -1.5, -1.5, 0, 3, 4.5]),
        .init(name: "Loudness", advanced: [6, 4, 0, 0, -2, 0, -1, -5, 5, 1]),
        .init(name: "Lounge", advanced: [-3, -1.5, -0.5, 1.5, 4, 2.5, 0, -1.5, 2, 1]),
        .init(name: "Piano", advanced: [3, 2, 0, 2.5, 3, 1.5, 3.5, 4.5, 3, 3.5]),
        .init(name: "Pop", advanced: [-1.5, -1, 0, 2, 4, 4, 2, 0, -1, -1.5]),
        .init(name: "R&B", advanced: [2.5, 7, 5.5, 1.5, -2, -1.5, 2.5, 2.5, 3, 3.5], preamp: -3),
        .init(name: "Rock", advanced: [5, 4, 3, 1.5, -0.5, -1, 0.5, 2.5, 3.5, 4.5]),
        .init(name: "Small Speakers", advanced: [5.5, 4, 3.5, 2.5, 1, 0, -1, -2.5, -3.5, -4]),
        .init(name: "Spoken Word", advanced: [-3.5, -0.5, 0, 0.5, 3.5, 4.5, 5, 4.5, 2.5, 0]),
        .init(name: "Treble Booster", advanced: [0, 0, 0, 0, 0, 1.5, 2.5, 3.5, 4.5, 5.5]),
        .init(name: "Treble Reducer", advanced: [0, 0, 0, 0, 0, -1.5, -2.5, -3.5, -4.5, -5.5]),
        .init(name: "Vocal Booster", advanced: [-1.5, -3, -3, 1.5, 3.5, 3.5, 3, 1.5, 0, -1.5]),
    ]

    static let basic: [EQPreset] = [
        .init(name: flatName, basic: BasicEQ()),
        .init(name: "Bass Boost", basic: BasicEQ(bass: 6, mid: 0, treble: 0)),
        .init(name: "Warm", basic: BasicEQ(bass: 3, mid: 1, treble: -2)),
        .init(name: "Bright", basic: BasicEQ(bass: -1, mid: 0, treble: 4)),
        .init(name: "V-Shape", basic: BasicEQ(bass: 5, mid: -3, treble: 4)),
        .init(name: "Voice", basic: BasicEQ(bass: -4, mid: 4, treble: 1)),
    ]

    static let expert: [EQPreset] = [
        .init(name: flatName, expert: ExpertEQ()),
        .init(name: "Rumble Filter", expert: ExpertEQ(bands: [
            EQBand(type: .highPass, frequency: 30, q: 0.71),
            EQBand(type: .peak, frequency: 180, gain: -1.5, q: 1),
        ])),
        .init(name: "Vocal Presence", expert: ExpertEQ(bands: [
            EQBand(type: .highPass, frequency: 80, q: 0.71),
            EQBand(type: .peak, frequency: 250, gain: -2, q: 1.2),
            EQBand(type: .peak, frequency: 3_000, gain: 3, q: 1),
            EQBand(type: .highShelf, frequency: 10_000, gain: 1.5, q: 0.7),
        ], preamp: -3)),
        .init(name: "Sub Bass", expert: ExpertEQ(bands: [
            EQBand(type: .lowShelf, frequency: 60, gain: 6, q: 0.8),
            EQBand(type: .peak, frequency: 250, gain: -1.5, q: 1.4),
        ], preamp: -6)),
        .init(name: "Harman-ish Tilt", expert: ExpertEQ(bands: [
            EQBand(type: .lowShelf, frequency: 105, gain: 4, q: 0.7),
            EQBand(type: .peak, frequency: 3_000, gain: 1.5, q: 1),
            EQBand(type: .highShelf, frequency: 10_000, gain: -2, q: 0.7),
        ], preamp: -4)),
        .init(name: "Night Mode", expert: ExpertEQ(bands: [
            EQBand(type: .lowShelf, frequency: 120, gain: -6, q: 0.7),
            EQBand(type: .peak, frequency: 2_500, gain: 2, q: 0.8),
            EQBand(type: .highShelf, frequency: 9_000, gain: -3, q: 0.7),
        ])),
        .init(name: "De-Esser", expert: ExpertEQ(bands: [
            EQBand(type: .peak, frequency: 6_500, gain: -4, q: 3),
            EQBand(type: .peak, frequency: 8_500, gain: -2, q: 3),
        ])),
    ]

    static func presets(for mode: EQMode) -> [EQPreset] {
        switch mode {
        case .basic: return basic
        case .advanced: return advanced
        case .expert: return expert
        }
    }
}
