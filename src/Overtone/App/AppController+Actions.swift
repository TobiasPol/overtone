import AppKit
import UniformTypeIdentifiers

/// User-triggered actions shared by several views.
extension AppController {
    func openSettings() {
        SettingsWindowController.shared.show(self)
    }

    func quit() {
        NSApp.terminate(nil)
    }

    /// Downloads an AutoEQ profile and makes it the active headphone correction.
    func applyAutoEQ(_ entry: AutoEQEntry) async throws {
        let profile = try await autoEQ.fetchProfile(entry)
        state.correction = HeadphoneCorrection(
            isEnabled: true, profileName: entry.name, source: entry.detail,
            preamp: profile.preamp, filters: profile.bands
        )
    }

    /// Moves the headphone correction into the Expert EQ so it can be edited band by band.
    func editCorrectionInExpertEQ() {
        let correction = state.correction
        guard !correction.filters.isEmpty else { return }
        var equalizer = state.equalizer
        equalizer.mode = .expert
        equalizer.expert = ExpertEQ(bands: Array(correction.filters.prefix(ExpertEQ.maxBands)), preamp: correction.preamp)
        equalizer.selectedPreset = correction.profileName
        state.equalizer = equalizer
        state.correction.isEnabled = false
    }

    func importCorrectionFile() {
        let url = withPinnedPopover {
            FilePanels.open(types: [.plainText], message: "Choose an AutoEQ / Equalizer APO ParametricEQ.txt file")
        }
        guard let url, let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        let profile = ParametricEQFormat.parse(text)
        guard !profile.bands.isEmpty else { return }
        state.correction = HeadphoneCorrection(
            isEnabled: true,
            profileName: url.deletingPathExtension().lastPathComponent.replacingOccurrences(of: " ParametricEQ", with: ""),
            source: "Imported file", preamp: profile.preamp, filters: profile.bands
        )
    }

    func importPresets() -> String? {
        let url = withPinnedPopover {
            FilePanels.open(types: [.json, .plainText], message: "Choose an Overtone preset or ParametricEQ.txt file")
        }
        guard let url else { return nil }
        do {
            let imported = try presets.importPresets(from: url)
            if let first = imported.first { first.apply(to: &state.equalizer) }
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func exportCurrentMode() {
        let mode = state.equalizer.mode
        let userPresets = presets.user(for: mode)
        let current = EQPreset(name: state.equalizer.selectedPreset ?? "Current", from: state.equalizer)
        let toExport = userPresets.isEmpty ? [current] : userPresets
        let url = withPinnedPopover { FilePanels.save(name: "Overtone \(mode.label) Presets.json", type: .json) }
        guard let url, let data = try? presets.exportData(toExport) else { return }
        try? data.write(to: url, options: .atomic)
    }

    func exportParametric() {
        let bands = ParamsBuilder.activeBands(DSPSettings(equalizer: state.equalizer, correction: state.correction))
        let profile = ParametricEQFormat.Profile(
            preamp: ParamsBuilder.preampDB(DSPSettings(equalizer: state.equalizer, correction: state.correction), bands: bands),
            bands: bands
        )
        let url = withPinnedPopover { FilePanels.save(name: "Overtone ParametricEQ.txt", type: .plainText) }
        guard let url else { return }
        try? ParametricEQFormat.render(profile).write(to: url, atomically: true, encoding: .utf8)
    }
}

@MainActor
enum FilePanels {
    static func open(types: [UTType], message: String) -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = types
        panel.allowsMultipleSelection = false
        panel.message = message
        NSApp.activate(ignoringOtherApps: true)
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func save(name: String, type: UTType) -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [type]
        panel.nameFieldStringValue = name
        NSApp.activate(ignoringOtherApps: true)
        return panel.runModal() == .OK ? panel.url : nil
    }
}
