import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab().tabItem { Label("General", systemImage: "gearshape") }
            InterfaceSettingsTab().tabItem { Label("Interface", systemImage: "paintpalette") }
            AboutTab().tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 480, height: 380)
    }
}

private struct GeneralSettingsTab: View {
    @Environment(AppState.self) private var state
    @Environment(AppController.self) private var controller
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchError: String?

    var body: some View {
        @Bindable var state = state
        Form {
            Section {
                Toggle("Open Overtone at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                if let launchError {
                    Text(launchError).font(.caption).foregroundStyle(.orange)
                }
                Toggle("Remember EQ and headphone correction per output device", isOn: $state.general.rememberPerDevice)
            }
            Section("Volume") {
                Picker("Maximum volume boost", selection: $state.output.maxBoost) {
                    ForEach(OutputSettings.boostChoices, id: \.self) { Text(Format.percent($0)).tag($0) }
                }
                Toggle(
                    "Use volume keys for outputs without volume control (HDMI, DisplayPort)",
                    isOn: $state.output.softwareVolumeKeys
                )
                if controller.volumeKeysNeedAccessibility {
                    HStack {
                        Text("Needs Accessibility permission to capture the volume keys.").font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Grant Access…") { controller.requestAccessibility() }.controlSize(.small)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLogin.set(enabled)
            launchError = nil
        } catch {
            launchError = error.localizedDescription
            launchAtLogin = LaunchAtLogin.isEnabled
        }
    }
}

private struct InterfaceSettingsTab: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        Form {
            Section("Accent Colour") {
                HStack(spacing: 8) {
                    ForEach(AccentChoice.allCases) { choice in swatch(choice) }
                }
            }
            Section("Display") {
                Toggle("Show spectrum analyzer", isOn: $state.general.showAnalyzer)
            }
            Section("Visible Sections") {
                ForEach(AppSection.allCases) { section in
                    Toggle(isOn: visibility(section)) { Label(section.label, systemImage: section.symbolName) }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func swatch(_ choice: AccentChoice) -> some View {
        Button { state.general.accent = choice } label: {
            Circle()
                .fill(choice.color ?? Color.accentColor)
                .overlay(Circle().strokeBorder(.white, lineWidth: state.general.accent == choice ? 2 : 0))
                .overlay(choice == .system ? Image(systemName: "gearshape.fill").font(.system(size: 8))
                    .foregroundStyle(.white) : nil)
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.plain)
        .help(choice.label)
    }

    private func visibility(_ section: AppSection) -> Binding<Bool> {
        Binding(
            get: { !state.general.hiddenSections.contains(section) },
            set: { visible in
                if visible {
                    state.general.hiddenSections.remove(section)
                } else if state.general.hiddenSections.count < AppSection.allCases.count - 1 {
                    state.general.hiddenSections.insert(section)
                }
            }
        )
    }
}

private struct AboutTab: View {
    @Environment(AppController.self) private var controller
    @State private var confirmReset = false

    var body: some View {
        VStack(spacing: 12) {
            AppIconArtwork(size: 88)
            Text("Overtone").font(.title2.weight(.semibold))
            Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")")
                .foregroundStyle(.secondary)
            Text(
                "A system-wide equalizer for macOS with parametric EQ, AutoEQ headphone correction, spatial audio, a per-app volume mixer and Audio Unit hosting."
            )
            .multilineTextAlignment(.center)
            .font(.callout)
            .frame(maxWidth: 360)
            Link("Headphone data from the AutoEQ project", destination: URL(string: "https://github.com/jaakkopasanen/AutoEq")!)
                .font(.callout)
            Spacer()
            Button("Reset All Settings…", role: .destructive) { confirmReset = true }
                .confirmationDialog("Reset all settings?", isPresented: $confirmReset) {
                    Button("Reset", role: .destructive) { controller.resetAllSettings() }
                } message: {
                    Text("Equalizer, effects, mixer and device profiles return to their defaults. Saved presets are kept.")
                }
        }
        .padding(24)
    }
}
