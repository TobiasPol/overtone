import Foundation
@testable import Overtone
import Testing

@MainActor
@Suite("Auto preset")
struct AutoPresetTests {
    let state = AppState()
    let auto: AutoPresetController

    init() {
        auto = AutoPresetController(state: state, dsp: DSPCore())
        auto.glideDuration = 0
        state.onChange = { [auto] change in if change == .dsp { auto.equalizerDidChange() } }
        state.equalizer.mode = .expert
        state.equalizer.expert.bands[0].gain = 3
        state.equalizer.selectedPreset = nil
    }

    private var userEQ: EqualizerSettings {
        var eq = EqualizerSettings()
        eq.mode = .expert
        eq.expert.bands[0].gain = 3
        return eq
    }

    @Test func appliedPresetIsNeverSaved() {
        auto.apply(.sound(.rock))
        #expect(state.equalizer.mode == .advanced)
        #expect(state.equalizer.selectedPreset == "Rock")
        #expect(state.persisted.equalizer == userEQ)
        state.storeProfile(for: "speakers")
        #expect(state.deviceProfiles["speakers"]?.equalizer == userEQ)
    }

    @Test func unclearMusicRestoresTheUsersEQ() {
        auto.apply(.musicApp(genre: "Jazz", preset: "Jazz"))
        #expect(state.equalizer.selectedPreset == "Jazz")
        auto.apply(.sound(.music))
        #expect(state.equalizer == userEQ)
        #expect(state.manualEqualizer == nil)
    }

    @Test func editingTheEQPausesAutoModeAndKeepsTheEdit() {
        auto.apply(.sound(.classical))
        state.equalizer.advanced.gains[0] += 1
        #expect(auto.isPaused)
        #expect(state.manualEqualizer == nil)
        #expect(state.persisted.equalizer.advanced.gains[0] == 5.5)
        auto.apply(.sound(.speech))
        #expect(!auto.isPaused)
        #expect(state.equalizer.selectedPreset == "Spoken Word")
    }

    @Test func togglingTheEqualizerKeepsAutoModeRunning() {
        auto.apply(.sound(.rock))
        state.equalizer.isEnabled = false
        #expect(!auto.isPaused)
        #expect(state.manualEqualizer?.isEnabled == false)
        #expect(state.equalizer.selectedPreset == "Rock")
    }

    @Test func deviceChangeStoresTheUsersEQWithTheOldDevice() {
        auto.apply(.sound(.electronic))
        auto.suspendForDeviceChange()
        #expect(state.equalizer == userEQ)
        #expect(state.manualEqualizer == nil)
    }

    @Test func turningAutoOffRestoresTheUsersEQ() {
        state.autoPreset.isEnabled = true
        auto.update()
        #expect(auto.detector.isRunning)
        auto.apply(.sound(.piano))
        state.autoPreset.isEnabled = false
        auto.update()
        #expect(!auto.detector.isRunning)
        #expect(state.equalizer == userEQ)
    }

    @Test func blendInterpolatesGainsAndPreamp() {
        let a = AdvancedEQ(gains: Array(repeating: 0, count: 10), preamp: 0)
        let b = AdvancedEQ(gains: Array(repeating: 4, count: 10), preamp: -2)
        let half = AutoPresetController.blend(a, b, 0.5)
        #expect(half.gains.allSatisfy { $0 == 2 })
        #expect(half.preamp == -1)
        #expect(AutoPresetController.blend(a, b, 1) == b)
    }
}
