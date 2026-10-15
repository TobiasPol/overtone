import SwiftUI

/// Per-application volume, mute and boost.
struct MixerSection: View {
    @Environment(AppState.self) private var state
    @Environment(VolumeMixer.self) private var mixer
    @Environment(AudioEngine.self) private var engine

    var body: some View {
        let apps = mixer.visibleApps(settings: state.mixer)
        VStack(spacing: 8) {
            if engine.status != .running {
                EmptyStateView(
                    systemImage: "square.stack.3d.up.slash",
                    title: "Mixer is paused",
                    message: "Turn Overtone on to control the volume of individual apps."
                )
            } else if apps.isEmpty {
                EmptyStateView(
                    systemImage: "speaker.zzz",
                    title: "Nothing is playing",
                    message: "Apps appear here while they play audio. Apps you adjust stay listed while they run."
                )
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(apps) { app in MixerRow(app: app) }
                    }
                }
            }
            Spacer(minLength: 0)
            if !state.mixer.apps.isEmpty {
                Button("Reset All Apps") { state.mixer.apps.removeAll() }
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .onAppear { mixer.setPolling(true) }
        .onDisappear { mixer.setPolling(false) }
    }
}

private struct MixerRow: View {
    @Environment(AppState.self) private var state
    let app: AudioApp

    private var setting: AppVolume { state.mixer.apps[app.id] ?? AppVolume() }

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: VolumeMixer.icon(for: app))
                .resizable()
                .frame(width: 24, height: 24)
                .overlay(alignment: .bottomTrailing) {
                    if app.isPlaying {
                        Circle().fill(.green).frame(width: 7, height: 7)
                            .overlay(Circle().strokeBorder(.background, lineWidth: 1.5))
                    }
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(app.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Slider(value: volume, in: 0...2).controlSize(.mini)
            }
            Text(setting.isMuted ? "Muted" : Format.percent(setting.volume))
                .font(.system(size: 10.5).monospacedDigit())
                .foregroundStyle(setting.volume > 1.001 ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                .frame(width: 40, alignment: .trailing)
            Button { update { $0.isMuted.toggle() } } label: {
                Image(systemName: setting.isMuted ? "speaker.slash.fill" : "speaker.wave.2")
                    .foregroundStyle(setting.isMuted ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                    .frame(width: 16)
            }
            .buttonStyle(.borderless)
            .help(setting.isMuted ? "Unmute \(app.name)" : "Mute \(app.name)")
            Button { state.mixer.apps[app.id] = nil } label: {
                Image(systemName: "arrow.counterclockwise").foregroundStyle(.tertiary)
            }
            .buttonStyle(.borderless)
            .opacity(state.mixer.apps[app.id] == nil ? 0 : 1)
            .disabled(state.mixer.apps[app.id] == nil)
            .help("Reset to 100%")
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.045)))
    }

    private var volume: Binding<Double> {
        Binding(
            get: { setting.volume },
            set: { value in update { $0.volume = abs(value - 1) < 0.03 ? 1 : value } }
        )
    }

    private func update(_ change: (inout AppVolume) -> Void) {
        var current = setting
        change(&current)
        state.mixer.apps[app.id] = current
    }
}
