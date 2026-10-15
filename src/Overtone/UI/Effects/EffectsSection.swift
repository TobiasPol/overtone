import SwiftUI

/// Spatial audio (room simulation), stereo tools and output protection.
struct EffectsSection: View {
    var body: some View {
        VStack(spacing: 10) {
            SpatialCard()
            StereoCard()
            ProtectionCard()
        }
        .padding(.bottom, 4)
    }
}

private struct SpatialCard: View {
    @Environment(AppState.self) private var state
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 4)

    var body: some View {
        @Bindable var state = state
        SectionCard(title: "Spatial Audio", systemImage: "cube.transparent") {
            Toggle("Spatial Audio", isOn: $state.spatial.roomEnabled).toggleStyle(.switch).controlSize(.mini).labelsHidden()
        } content: {
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(RoomPreset.allCases) { preset in
                    Button { state.spatial.apply(preset) } label: {
                        Text(preset.label)
                            .font(.system(size: 10.5, weight: .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(state.spatial
                                        .room == preset ? AnyShapeStyle(.tint.opacity(0.3)) :
                                        AnyShapeStyle(Color.primary.opacity(0.06)))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            Group {
                ParameterSlider(title: "Room Size", value: custom(\.roomSize), range: 0...1, format: Format.percent)
                ParameterSlider(title: "Damping", value: custom(\.damping), range: 0...1, format: Format.percent)
                ParameterSlider(title: "Mix", value: custom(\.mix), range: 0...0.8, format: Format.percent)
                ParameterSlider(title: "Pre-delay", value: custom(\.predelayMs), range: 0...100) { "\(Int($0)) ms" }
                ParameterSlider(title: "Spread", value: custom(\.roomWidth), range: 0...1, format: Format.percent)
            }
            .disabled(!state.spatial.roomEnabled)
            .opacity(state.spatial.roomEnabled ? 1 : 0.5)
        }
    }

    /// Editing a parameter by hand turns the preset selection into "custom".
    private func custom(_ keyPath: WritableKeyPath<SpatialSettings, Double>) -> Binding<Double> {
        Binding(
            get: { state.spatial[keyPath: keyPath] },
            set: { value in
                var spatial = state.spatial
                spatial[keyPath: keyPath] = value
                spatial.room = nil
                state.spatial = spatial
            }
        )
    }
}

private struct StereoCard: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        SectionCard("Stereo", systemImage: "arrow.left.and.right") {
            ParameterSlider(title: "Width", value: $state.spatial.width, range: 0...2, defaultValue: 1, format: Format.percent)
            Divider()
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Headphone Crossfeed").font(.system(size: 12))
                    Text("Blends a little of each channel into the other ear for a more natural image.")
                        .captionStyle().fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Toggle("Crossfeed", isOn: $state.spatial.crossfeedEnabled).toggleStyle(.switch).controlSize(.mini).labelsHidden()
            }
            Group {
                ParameterSlider(
                    title: "Amount",
                    value: $state.spatial.crossfeed,
                    range: 0...1,
                    defaultValue: 0.5,
                    format: Format.percent
                )
                ParameterSlider(title: "Cutoff", value: $state.spatial.crossfeedCutoff, range: 300...2_000, defaultValue: 700) {
                    "\(Int($0)) Hz"
                }
            }
            .disabled(!state.spatial.crossfeedEnabled)
            .opacity(state.spatial.crossfeedEnabled ? 1 : 0.5)
        }
    }
}

private struct ProtectionCard: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        SectionCard("Protection", systemImage: "shield.lefthalf.filled") {
            Toggle(isOn: $state.output.limiterEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Limiter").font(.system(size: 12))
                    Text("Catches peaks from EQ boosts and volume boost before they clip.").captionStyle()
                }
            }
            .toggleStyle(.switch).controlSize(.mini)
            ParameterSlider(title: "Ceiling", value: $state.output.limiterCeilingDB, range: -6...0, defaultValue: -0.3) {
                String(format: "%.1f dB", $0)
            }
            .disabled(!state.output.limiterEnabled)
            .opacity(state.output.limiterEnabled ? 1 : 0.5)
            Divider()
            Toggle(isOn: $state.equalizer.autoGain) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Auto Gain").font(.system(size: 12))
                    Text("Lowers the preamp by the EQ's highest boost, so nothing clips.").captionStyle()
                }
            }
            .toggleStyle(.switch).controlSize(.mini)
        }
    }
}
