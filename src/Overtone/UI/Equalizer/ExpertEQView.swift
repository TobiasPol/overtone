import SwiftUI

/// Fully parametric bands: type, frequency, gain and Q per band.
struct ExpertEQView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        let bands = state.equalizer.expert.bands
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Text("Preamp").captionStyle()
                Slider(value: $state.equalizer.expert.preamp, in: -24...12).controlSize(.mini)
                Text("\(Format.gain(state.equalizer.expert.preamp)) dB")
                    .font(.system(size: 11).monospacedDigit()).foregroundStyle(.secondary).frame(width: 52, alignment: .trailing)
                Toggle("Auto", isOn: $state.equalizer.autoGain)
                    .toggleStyle(.checkbox).controlSize(.small)
                    .help("Automatically lower the preamp so boosts never clip")
            }
            header
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(Array(bands.enumerated()), id: \.element.id) { index, band in
                        BandRow(index: index, band: binding(for: band.id)) { remove(band.id) }
                    }
                }
            }
            .frame(maxHeight: .infinity)
            Button {
                state.equalizer.expert.bands.append(state.equalizer.expert.suggestedBand())
            } label: {
                Label("Add Band", systemImage: "plus")
            }
            .controlSize(.small)
            .disabled(bands.count >= ExpertEQ.maxBands)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 182)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text("Band").frame(width: 34, alignment: .leading)
            Text("Type").frame(width: 92, alignment: .leading)
            Text("Freq Hz").frame(width: 58, alignment: .trailing)
            Text("Gain dB").frame(width: 50, alignment: .trailing)
            Text("Q").frame(width: 44, alignment: .trailing)
            Spacer()
        }
        .font(.system(size: 9.5, weight: .medium))
        .foregroundStyle(.tertiary)
    }

    private func binding(for id: UUID) -> Binding<EQBand> {
        Binding(
            get: { state.equalizer.expert.bands.first { $0.id == id } ?? EQBand() },
            set: { updated in
                guard let i = state.equalizer.expert.bands.firstIndex(where: { $0.id == id }) else { return }
                state.equalizer.expert.bands[i] = updated.clamped()
            }
        )
    }

    private func remove(_ id: UUID) {
        state.equalizer.expert.bands.removeAll { $0.id == id }
    }
}

private struct BandRow: View {
    let index: Int
    @Binding var band: EQBand
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 4) {
                Circle().fill(BandPalette.color(index)).frame(width: 8, height: 8)
                Toggle("Enabled", isOn: $band.isEnabled).toggleStyle(.checkbox).labelsHidden()
            }
            .frame(width: 34, alignment: .leading)
            Picker("Type", selection: $band.type) {
                ForEach(FilterType.allCases) { Text($0.label).tag($0) }
            }
            .labelsHidden()
            .frame(width: 92)
            NumberField(value: $band.frequency, width: 58, fractionDigits: 0...0)
            NumberField(value: $band.gain, width: 50, fractionDigits: 0...1)
                .disabled(!band.type.usesGain)
                .opacity(band.type.usesGain ? 1 : 0.4)
            NumberField(value: $band.q, width: 44, fractionDigits: 0...2)
            Spacer(minLength: 0)
            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
            }
            .buttonStyle(.borderless)
            .help("Remove band")
        }
        .controlSize(.small)
        .font(.system(size: 11))
    }
}
