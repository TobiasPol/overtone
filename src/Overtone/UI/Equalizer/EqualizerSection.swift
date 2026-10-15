import SwiftUI

struct EqualizerSection: View {
    @Environment(AppState.self) private var state
    @State private var isSavingPreset = false

    var body: some View {
        @Bindable var state = state
        VStack(spacing: 10) {
            EQGraphView()
            if isSavingPreset {
                PresetSaveBar(isPresented: $isSavingPreset)
            } else {
                HStack(spacing: 8) {
                    Toggle("Equalizer", isOn: $state.equalizer.isEnabled)
                        .toggleStyle(.switch).controlSize(.mini).labelsHidden()
                        .help("Turn the equalizer on or off")
                    Picker("Mode", selection: $state.equalizer.mode) {
                        ForEach(EQMode.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 196)
                    Spacer(minLength: 0)
                    PresetMenu(isSaving: $isSavingPreset)
                }
            }
            Group {
                switch state.equalizer.mode {
                case .basic: BasicEQView()
                case .advanced: AdvancedEQView()
                case .expert: ExpertEQView()
                }
            }
            .disabled(!state.equalizer.isEnabled)
            .opacity(state.equalizer.isEnabled ? 1 : 0.5)
        }
    }
}

struct BasicEQView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        HStack(spacing: 0) {
            knob("Bass", "Low shelf · 120 Hz", value: $state.equalizer.basic.bass)
            knob("Mids", "Peak · 1 kHz", value: $state.equalizer.basic.mid)
            knob("Treble", "High shelf · 6 kHz", value: $state.equalizer.basic.treble)
        }
        .padding(.top, 8)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func knob(_ title: String, _ detail: String, value: Binding<Double>) -> some View {
        VStack(spacing: 6) {
            Knob(value: value, range: BasicEQ.range)
            Text(title).font(.system(size: 12, weight: .semibold))
            Text("\(Format.gain(value.wrappedValue)) dB").font(.system(size: 11).monospacedDigit()).foregroundStyle(.secondary)
            Text(detail).font(.system(size: 9)).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct AdvancedEQView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        HStack(alignment: .bottom, spacing: 0) {
            column("Pre", value: $state.equalizer.advanced.preamp)
            Rectangle().fill(Color.primary.opacity(0.1)).frame(width: 1, height: 130).padding(.horizontal, 3)
            ForEach(AdvancedEQ.frequencies.indices, id: \.self) { index in
                column(AdvancedEQ.label(for: AdvancedEQ.frequencies[index]), value: $state.equalizer.advanced.gains[index])
            }
        }
        .frame(height: 176)
    }

    private func column(_ label: String, value: Binding<Double>) -> some View {
        VStack(spacing: 4) {
            Text(String(format: "%+.1f", value.wrappedValue))
                .font(.system(size: 8.5).monospacedDigit())
                .foregroundStyle(abs(value.wrappedValue) < 0.05 ? .tertiary : .secondary)
            VerticalSlider(value: value, range: AdvancedEQ.range)
            Text(label).font(.system(size: 9.5, weight: .medium))
        }
        .frame(maxWidth: .infinity)
    }
}
