import SwiftUI

/// Always-visible volume (with boost), balance and output device controls.
struct OutputFooter: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(spacing: 8) {
            volumeRow
            balanceRow
            DevicePicker()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var volumeRow: some View {
        HStack(spacing: 8) {
            Button { state.output.isMuted.toggle() } label: {
                Image(systemName: volumeSymbol).frame(width: 18)
            }
            .buttonStyle(.borderless)
            .help(state.output.isMuted ? "Unmute" : "Mute")
            Slider(value: volumeBinding, in: 0...state.output.maxBoost).controlSize(.small)
            Text(state.output.isMuted ? "Muted" : Format.percent(state.output.volume))
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(state.output.volume > 1.001 && !state.output
                    .isMuted ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                .frame(width: 44, alignment: .trailing)
                .help(state.output.volume > 1 ? "Volume boost is active" : "Overtone volume")
        }
    }

    private var balanceRow: some View {
        HStack(spacing: 8) {
            Text("L").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary).frame(width: 18)
            Slider(value: balanceBinding, in: -1...1).controlSize(.small)
            Text(balanceLabel)
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)
                .onTapGesture(count: 2) { state.output.balance = 0 }
                .help("Balance · double-click to centre")
        }
    }

    private var volumeSymbol: String {
        let v = state.output.volume
        if state.output.isMuted || v == 0 { return "speaker.slash.fill" }
        if v < 0.34 { return "speaker.wave.1.fill" }
        if v < 0.67 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }

    /// Snaps to 100 % so it's easy to return to unity gain.
    private var volumeBinding: Binding<Double> {
        Binding(
            get: { state.output.volume },
            set: { state.output.volume = abs($0 - 1) < 0.025 ? 1 : $0 }
        )
    }

    private var balanceBinding: Binding<Double> {
        Binding(
            get: { state.output.balance },
            set: { state.output.balance = abs($0) < 0.04 ? 0 : $0 }
        )
    }

    private var balanceLabel: String {
        let b = state.output.balance
        if abs(b) < 0.005 { return "Center" }
        return b < 0 ? "L \(Int((-b * 100).rounded()))" : "R \(Int((b * 100).rounded()))"
    }
}

struct DevicePicker: View {
    @Environment(AudioEngine.self) private var engine

    var body: some View {
        Menu {
            ForEach(engine.devices) { device in
                Button {
                    engine.selectOutput(device)
                } label: {
                    Label(device.name, systemImage: device.id == engine.outputDevice?.id ? "checkmark" : device.symbolName)
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: engine.outputDevice?.symbolName ?? "hifispeaker")
                    .frame(width: 18)
                Text(engine.outputDevice?.name ?? "No Output")
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
            }
            .font(.system(size: 12))
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.primary.opacity(0.06)))
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .help("Output device")
    }
}
