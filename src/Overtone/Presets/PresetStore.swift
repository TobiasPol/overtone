import Foundation
import Observation

/// Built-in presets plus the user's own, persisted as presets.json.
@MainActor @Observable
final class PresetStore {
    private(set) var userPresets: [EQPreset] = []
    @ObservationIgnored private let url = SettingsStore.directory.appendingPathComponent("presets.json")

    init() {
        if let data = try? Data(contentsOf: url),
           let presets = try? JSONDecoder().decode([EQPreset].self, from: data) {
            userPresets = presets
        }
    }

    func builtIn(for mode: EQMode) -> [EQPreset] {
        BuiltInPresets.presets(for: mode)
    }

    func user(for mode: EQMode) -> [EQPreset] {
        userPresets.filter { $0.mode == mode }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func isUserPreset(named name: String?, mode: EQMode) -> Bool {
        guard let name else { return false }
        return userPresets.contains { $0.mode == mode && $0.name == name }
    }

    /// Saves the active mode's settings under `name`, replacing a user preset with the same name.
    @discardableResult
    func save(name: String, from equalizer: EqualizerSettings) -> EQPreset {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var preset = EQPreset(name: trimmed.isEmpty ? "Untitled" : trimmed, from: equalizer)
        if let index = userPresets.firstIndex(where: { $0.mode == preset.mode && $0.name == preset.name }) {
            preset.id = userPresets[index].id
            userPresets[index] = preset
        } else {
            userPresets.append(preset)
        }
        persist()
        return preset
    }

    func delete(named name: String, mode: EQMode) {
        userPresets.removeAll { $0.mode == mode && $0.name == name }
        persist()
    }

    func exportData(_ presets: [EQPreset]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(presets)
    }

    /// Imports Overtone JSON (one preset or a list) or an Equalizer APO / AutoEQ text file.
    func importPresets(from file: URL) throws -> [EQPreset] {
        let data = try Data(contentsOf: file)
        let imported: [EQPreset]
        if let list = try? JSONDecoder().decode([EQPreset].self, from: data) {
            let sanitized = list.compactMap(Self.validated)
            guard !sanitized.isEmpty else { throw ImportError.unrecognized }
            imported = sanitized
        } else if let single = try? JSONDecoder().decode(EQPreset.self, from: data) {
            guard let sanitized = Self.validated(single) else { throw ImportError.unrecognized }
            imported = [sanitized]
        } else if let text = String(data: data, encoding: .utf8) {
            let profile = ParametricEQFormat.parse(text)
            guard !profile.bands.isEmpty else { throw ImportError.unrecognized }
            let name = file.deletingPathExtension().lastPathComponent.replacingOccurrences(of: " ParametricEQ", with: "")
            let bands = Array(profile.bands.prefix(ExpertEQ.maxBands))
            imported = [EQPreset(name: name, expert: ExpertEQ(bands: bands, preamp: profile.preamp))]
        } else {
            throw ImportError.unrecognized
        }
        for preset in imported {
            var copy = preset
            copy.id = UUID()
            userPresets.removeAll { $0.mode == copy.mode && $0.name == copy.name }
            userPresets.append(copy)
        }
        persist()
        return imported
    }

    enum ImportError: LocalizedError {
        case unrecognized
        var errorDescription: String? { "The file isn't an Overtone preset or an Equalizer APO parametric EQ." }
    }

    private static func validated(_ preset: EQPreset) -> EQPreset? {
        var copy = preset
        let trimmed = copy.name.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.name = trimmed.isEmpty ? "Untitled" : trimmed
        switch copy.mode {
        case .basic:
            guard var b = copy.basic else { return nil }
            b.bass = (b.bass.isFinite ? b.bass : 0).clamped(to: BasicEQ.range)
            b.mid = (b.mid.isFinite ? b.mid : 0).clamped(to: BasicEQ.range)
            b.treble = (b.treble.isFinite ? b.treble : 0).clamped(to: BasicEQ.range)
            copy.basic = b
        case .advanced:
            guard let a = copy.advanced else { return nil }
            copy.advanced = AdvancedEQ(gains: a.gains, preamp: a.preamp)
        case .expert:
            guard var e = copy.expert else { return nil }
            e.bands = Array(e.bands.prefix(ExpertEQ.maxBands)).map { $0.clamped() }
            e.preamp = (e.preamp.isFinite ? e.preamp : 0).clamped(to: -24...12)
            copy.expert = e
        }
        return copy
    }

    private func persist() {
        guard let data = try? exportData(userPresets) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
