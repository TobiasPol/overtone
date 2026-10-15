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
            imported = list
        } else if let single = try? JSONDecoder().decode(EQPreset.self, from: data) {
            imported = [single]
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

    private func persist() {
        guard let data = try? exportData(userPresets) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
