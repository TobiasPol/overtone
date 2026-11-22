import SwiftUI

/// Preset picker for the active EQ mode, with save/delete/import/export.
struct PresetMenu: View {
    @Environment(AppState.self) private var state
    @Environment(PresetStore.self) private var presets
    @Environment(AppController.self) private var controller
    @Environment(AutoPresetController.self) private var autoPreset
    @Environment(MusicTypeDetector.self) private var detector
    @Binding var isSaving: Bool
    @Binding var importError: String?

    var body: some View {
        @Bindable var state = state
        let mode = state.equalizer.mode
        Menu {
            Toggle("Choose Automatically", isOn: $state.autoPreset.isEnabled)
            if state.autoPreset.isEnabled {
                Text(autoStatus)
            }
            Divider()
            Section("Built-in") {
                ForEach(presets.builtIn(for: mode)) { preset in button(for: preset, isUser: false) }
            }
            let user = presets.user(for: mode)
            if !user.isEmpty {
                Section("My Presets") {
                    ForEach(user) { preset in button(for: preset, isUser: true) }
                }
            }
            Divider()
            Button("Save Preset…") { isSaving = true }
            if let name = state.equalizer.selectedPreset, presets.isUserPreset(named: name, mode: mode),
               !presets.builtIn(for: mode).contains(where: { $0.name == name && $0.matches(state.equalizer) }) {
                Button("Delete “\(name)”", role: .destructive) {
                    presets.delete(named: name, mode: mode)
                    state.equalizer.selectedPreset = nil
                }
            }
            Divider()
            Button("Import Preset…") { importError = controller.importPresets() }
            Button("Export \(mode.label) Presets…") { controller.exportCurrentMode() }
            Button("Export as ParametricEQ.txt…") { controller.exportParametric() }
        } label: {
            if state.autoPreset.isEnabled {
                Label(autoTitle ?? title, systemImage: autoTitle == nil ? "wand.and.stars.inverse" : "wand.and.stars")
                    .font(.system(size: 12, weight: .medium)).lineLimit(1)
            } else {
                Text(title).font(.system(size: 12, weight: .medium)).lineLimit(1)
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(state.autoPreset.isEnabled ? "Auto preset: \(autoStatus)" : "Presets")
    }

    private func button(for preset: EQPreset, isUser: Bool) -> some View {
        Button {
            preset.apply(to: &state.equalizer)
        } label: {
            if isSelected(preset, isUser: isUser) {
                Label(preset.name, systemImage: "checkmark")
            } else {
                Text(preset.name)
            }
        }
    }

    /// The preset auto mode applied, if it is the one playing right now.
    private var autoTitle: String? {
        guard autoPreset.isActive, !autoPreset.isPaused else { return nil }
        return detector.detection?.presetName
    }

    private var autoStatus: String {
        guard autoPreset.isActive else { return "Off while Overtone is off" }
        if autoPreset.isPaused { return "Paused until the music changes" }
        guard let detection = detector.detection else { return "Listening…" }
        return "\(detection.label) · \(detection.detail)"
    }

    private func isSelected(_ preset: EQPreset, isUser: Bool) -> Bool {
        guard state.equalizer.selectedPreset == preset.name else { return false }
        let mode = state.equalizer.mode
        if presets.user(for: mode).contains(where: { $0.name == preset.name && $0.matches(state.equalizer) }) {
            return isUser
        }
        if presets.builtIn(for: mode).contains(where: { $0.name == preset.name && $0.matches(state.equalizer) }) {
            return !isUser
        }
        return isUser || !presets.isUserPreset(named: preset.name, mode: mode)
    }

    private var title: String {
        let mode = state.equalizer.mode
        let all = presets.builtIn(for: mode) + presets.user(for: mode)
        guard let name = state.equalizer.selectedPreset else {
            if let flat = all.first(where: { $0.name == BuiltInPresets.flatName && $0.matches(state.equalizer) }) {
                return flat.name
            }
            return "Custom"
        }
        if all.contains(where: { $0.name == name && $0.matches(state.equalizer) }) { return name }
        return all.contains(where: { $0.name == name }) ? "\(name) (edited)" : name
    }
}

/// Inline "name your preset" row (alerts are unreliable inside status-bar popovers).
struct PresetSaveBar: View {
    @Environment(AppState.self) private var state
    @Environment(PresetStore.self) private var presets
    @Binding var isPresented: Bool
    @State private var name = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            TextField("Preset name", text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit(save)
            Button("Cancel") { isPresented = false }.keyboardShortcut(.cancelAction)
            Button("Save", action: save)
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .controlSize(.small)
        .onAppear {
            name = state.equalizer.selectedPreset ?? ""
            focused = true
        }
    }

    private func save() {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let preset = presets.save(name: name, from: state.equalizer)
        state.equalizer.selectedPreset = preset.name
        isPresented = false
    }
}
