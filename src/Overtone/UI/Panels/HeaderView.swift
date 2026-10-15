import SwiftUI

struct HeaderView: View {
    @Environment(AppState.self) private var state
    @Environment(AudioEngine.self) private var engine
    @Environment(AppController.self) private var controller

    var body: some View {
        @Bindable var state = state
        HStack(spacing: 10) {
            AppGlyph(active: state.isEnabled)
            VStack(alignment: .leading, spacing: 1) {
                Text("Overtone").font(.system(size: 13, weight: .semibold))
                Text(statusLine)
                    .font(.system(size: 10.5))
                    .foregroundStyle(statusIsProblem ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 6)
            if engine.status == .running {
                LevelMeter()
            }
            Toggle("Overtone", isOn: $state.isEnabled)
                .toggleStyle(.switch).controlSize(.small).labelsHidden()
                .help(state.isEnabled ? "Turn processing off" : "Turn processing on")
            Menu {
                Button("Settings…") { controller.openSettings() }
                Divider()
                Button("Quit Overtone") { controller.quit() }
            } label: {
                Image(systemName: "gearshape").font(.system(size: 13))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private var statusIsProblem: Bool {
        switch engine.status {
        case .failed, .permissionDenied: return true
        default: return false
        }
    }

    private var statusLine: String {
        switch engine.status {
        case .off: return "Off · audio plays unprocessed"
        case .starting: return "Starting…"
        case .running:
            return "\(engine.outputDevice?.name ?? "Output") · \(Format.sampleRate(engine.context.sampleRate))"
        case .awaitingPermission: return "Waiting for permission…"
        case .permissionDenied: return "System audio recording is not allowed"
        case let .failed(message): return message
        }
    }
}

/// Explains blocking problems and offers the fix.
struct StatusBanner: View {
    @Environment(AudioEngine.self) private var engine

    var body: some View {
        switch engine.status {
        case .permissionDenied:
            banner(
                "Overtone needs “System Audio Recording” permission to process sound. Enable it in Privacy & Security, then try again.",
                primary: ("Open Settings", { NSWorkspace.shared.open(AudioCapturePermission.settingsURL) })
            )
        case .failed:
            banner(
                "Audio processing stopped. Your sound is playing normally without effects.",
                primary: ("Retry", { engine.retry() })
            )
        default:
            EmptyView()
        }
    }

    private func banner(_ text: String, primary: (String, () -> Void)) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 8) {
                Text(text).font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button(primary.0, action: primary.1).controlSize(.small)
                    if engine.status == .permissionDenied {
                        Button("Try Again") { engine.retry() }.controlSize(.small)
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color.orange.opacity(0.12)))
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }
}

struct AppGlyph: View {
    var active = true
    var size: CGFloat = 28

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
            .fill(LinearGradient(
                colors: active ? [Color(red: 0.36, green: 0.42, blue: 1), Color(red: 0.75, green: 0.32, blue: 0.95)]
                    : [.gray.opacity(0.6), .gray.opacity(0.4)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ))
            .overlay(
                Image(systemName: "slider.vertical.3")
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundStyle(.white)
            )
            .frame(width: size, height: size)
    }
}

/// Tiny stereo output meter.
private struct LevelMeter: View {
    @Environment(SpectrumAnalyzer.self) private var analyzer

    var body: some View {
        HStack(spacing: 2) {
            bar(analyzer.meters.left)
            bar(analyzer.meters.right)
        }
        .frame(width: 9, height: 22)
        .help("Output level")
    }

    private func bar(_ level: Float) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                Capsule().fill(Color.primary.opacity(0.1))
                Capsule()
                    .fill(level > 0.97 ? Color.red : level > 0.85 ? Color.yellow : Color.green)
                    .frame(height: geo.size.height * CGFloat(level))
            }
        }
    }
}
