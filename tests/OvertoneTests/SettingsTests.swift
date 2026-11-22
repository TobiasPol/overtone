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
        let nanBand = EQBand(frequency: .nan, gain: .nan, q: .infinity).clamped()
        #expect(nanBand.frequency == 1_000 && nanBand.gain == 0 && nanBand.q == 1)
    }

    @Test func advancedEQNormalizesShortDecodedGainsAndOutputSettingsClamps() throws {
        let shortJSON = Data(#"{"gains":[20,-20],"preamp":99}"#.utf8)
        let adv = try JSONDecoder().decode(AdvancedEQ.self, from: shortJSON)
        #expect(adv.gains.count == AdvancedEQ.frequencies.count)
        #expect(adv.gains[0] == 12 && adv.gains[1] == -12 && adv.gains[2] == 0)
        #expect(adv.preamp == 12)

        let outJSON = Data(#"{"volume":9,"maxBoost":1.5,"balance":-5}"#.utf8)
        let out = try JSONDecoder().decode(OutputSettings.self, from: outJSON)
        #expect(out.maxBoost == 1.5 && out.volume == 1.5 && out.balance == -1)
    }

    @Test func suggestedBandIgnoresInvalidFrequenciesAndFormatGainAvoidsNegativeZero() {
        let eq = ExpertEQ(bands: [EQBand(frequency: .nan), EQBand(frequency: -50)])
        let suggested = eq.suggestedBand()
        #expect(suggested.frequency.isFinite && EQBand.frequencyRange.contains(suggested.frequency))
        #expect(Format.gain(-0.01) == "0.0")
        #expect(Format.gain(0.01) == "0.0")
        #expect(Format.gain(1.5) == "+1.5")
    }

    @Test @MainActor func loadProfileUpdatesAtomicallyWithoutNotifications() {
        let state = AppState()
        var changes: [AppState.Change] = []
        state.onChange = { changes.append($0) }
        var customEQ = EqualizerSettings()
        customEQ.basic.bass = 6
        let customCorr = HeadphoneCorrection(profileName: "HD 650", filters: [EQBand(gain: 3)])
        state.deviceProfiles["dev-a"] = DeviceProfile(equalizer: customEQ, correction: customCorr)
        changes.removeAll()

        #expect(state.loadProfile(for: "dev-a"))
        #expect(state.equalizer.basic.bass == 6)
        #expect(state.correction.profileName == "HD 650")
        #expect(changes.isEmpty)
        #expect(!state.loadProfile(for: "unknown"))
    }
}
