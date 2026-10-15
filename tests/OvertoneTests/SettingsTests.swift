import Foundation
@testable import Overtone
import Testing

@Suite("Presets and persistence")
struct SettingsTests {
    @Test func builtInGraphicPresetsHaveTenBands() {
        for preset in BuiltInPresets.advanced {
            #expect(preset.advanced?.gains.count == AdvancedEQ.frequencies.count, "\(preset.name)")
        }
        #expect(BuiltInPresets.presets(for: .expert).allSatisfy { $0.expert != nil })
    }

    @Test func applyingPresetSwitchesModeAndMatches() {
        var eq = EqualizerSettings()
        eq.mode = .basic
        let rock = BuiltInPresets.advanced.first { $0.name == "Rock" }!
        rock.apply(to: &eq)
        #expect(eq.mode == .advanced)
        #expect(eq.selectedPreset == "Rock")
        #expect(rock.matches(eq))
        eq.advanced.gains[0] += 1
        #expect(!rock.matches(eq))
    }

    @Test func expertPresetMatchingIgnoresBandIdentity() {
        let preset = BuiltInPresets.expert.first { $0.name == "Vocal Presence" }!
        var eq = EqualizerSettings()
        preset.apply(to: &eq)
        eq.expert.bands = eq.expert.bands.map { var b = $0; b.id = UUID(); return b }
        #expect(preset.matches(eq))
    }

    @Test func persistedStateSurvivesDamagedSection() throws {
        var state = PersistedState()
        state.output.volume = 1.5
        state.equalizer.mode = .expert
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as! [String: Any]
        json["spatial"] = ["roomEnabled": "not a bool"]
        json.removeValue(forKey: "mixer")
        let decoded = try JSONDecoder().decode(PersistedState.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(decoded.output.volume == 1.5)
        #expect(decoded.equalizer.mode == .expert)
        #expect(decoded.spatial == SpatialSettings())
        #expect(decoded.mixer == MixerSettings())
    }

    @Test func suggestedExpertBandFillsWidestGap() {
        let eq = ExpertEQ(bands: [EQBand(frequency: 100), EQBand(frequency: 200)])
        let band = eq.suggestedBand()
        #expect(band.frequency > 1_000 && band.frequency < 10_000)
    }

    @Test func roomPresetUpdatesParameters() {
        var spatial = SpatialSettings()
        spatial.apply(.cathedral)
        #expect(spatial.room == .cathedral)
        #expect(spatial.roomSize > 0.9)
    }

    @Test func bandClampingKeepsFiltersSafe() {
        let band = EQBand(frequency: 5, gain: 99, q: 0).clamped()
        #expect(band.frequency == 20 && band.gain == 24 && band.q == 0.1)
    }
}
