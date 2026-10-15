import SwiftUI

/// Maps between frequency/gain and graph coordinates (log frequency, linear dB).
struct GraphScale {
    let size: CGSize
    let dbRange: Double
    private let inset: CGFloat = 8

    func x(_ frequency: Double) -> CGFloat {
        CGFloat((log10(max(frequency, 20)) - log10(20.0)) / 3) * size.width
    }

    func frequency(atX x: CGFloat) -> Double {
        pow(10, log10(20.0) + Double(x / max(size.width, 1)) * 3)
    }

    func y(_ db: Double) -> CGFloat {
        size.height / 2 - CGFloat(db / dbRange) * (size.height / 2 - inset)
    }

    func db(atY y: CGFloat) -> Double {
        Double((size.height / 2 - y) / (size.height / 2 - inset)) * dbRange
    }
}

/// Frequency response of the whole EQ stage, with the live spectrum behind it
/// and draggable band handles in Expert mode.
struct EQGraphView: View {
    @Environment(AppState.self) private var state

    private var dbRange: Double {
        state.equalizer.mode == .expert || state.correction.isActive ? 24 : 15
    }

    var body: some View {
        GeometryReader { geo in
            let scale = GraphScale(size: geo.size, dbRange: dbRange)
            ZStack {
                GridLayer(scale: scale)
                if state.general.showAnalyzer && state.isEnabled {
                    SpectrumLayer(scale: scale)
                }
                CurveLayer(scale: scale)
                if state.equalizer.mode == .expert && state.equalizer.isEnabled {
                    BandHandlesLayer(scale: scale)
                }
            }
            .coordinateSpace(name: "eqgraph")
        }
        .frame(height: 128)
        .background(Color.black.opacity(0.22))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
    }
}

private struct GridLayer: View {
    let scale: GraphScale
    private let lines: [Double] = [50, 100, 200, 500, 1_000, 2_000, 5_000, 10_000]
    private let labelled: Set<Double> = [100, 1_000, 10_000]

    var body: some View {
        Canvas { context, size in
            var grid = Path()
            for f in lines {
                grid.move(to: CGPoint(x: scale.x(f), y: 0))
                grid.addLine(to: CGPoint(x: scale.x(f), y: size.height))
            }
            for db in [-scale.dbRange / 2, scale.dbRange / 2] {
                grid.move(to: CGPoint(x: 0, y: scale.y(db)))
                grid.addLine(to: CGPoint(x: size.width, y: scale.y(db)))
            }
            context.stroke(grid, with: .color(.white.opacity(0.06)), lineWidth: 1)
            var zero = Path()
            zero.move(to: CGPoint(x: 0, y: scale.y(0)))
            zero.addLine(to: CGPoint(x: size.width, y: scale.y(0)))
            context.stroke(zero, with: .color(.white.opacity(0.14)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            for f in lines where labelled.contains(f) {
                context.draw(label(Format.frequency(f)), at: CGPoint(x: scale.x(f) + 3, y: size.height - 7), anchor: .leading)
            }
            let top = Format.gain(scale.dbRange / 2, decimals: 0)
            context.draw(label(top), at: CGPoint(x: 4, y: scale.y(scale.dbRange / 2) - 6), anchor: .leading)
        }
        .allowsHitTesting(false)
    }

    private func label(_ text: String) -> Text {
        Text(text).font(.system(size: 8, weight: .medium)).foregroundColor(.white.opacity(0.35))
    }
}

private struct SpectrumLayer: View {
    @Environment(SpectrumAnalyzer.self) private var analyzer
    let scale: GraphScale

    var body: some View {
        Canvas { context, size in
            let levels = analyzer.levels
            let edges = ResponseCurve.frequencies(count: levels.count + 1)
            let gradient = Gradient(colors: [.white.opacity(0.22), .white.opacity(0.05)])
            for (index, level) in levels.enumerated() where level > 0.005 {
                let x0 = scale.x(edges[index]) + 0.5
                let x1 = scale.x(edges[index + 1]) - 0.5
                let height = CGFloat(level) * size.height
                let rect = CGRect(x: x0, y: size.height - height, width: max(1, x1 - x0), height: height)
                context.fill(
                    Path(roundedRect: rect, cornerRadius: 1),
                    with: .linearGradient(
                        gradient,
                        startPoint: CGPoint(x: 0, y: rect.minY),
                        endPoint: CGPoint(x: 0, y: size.height)
                    )
                )
            }
        }
        .allowsHitTesting(false)
    }
}

private struct CurveLayer: View {
    @Environment(AppState.self) private var state
    let scale: GraphScale

    var body: some View {
        // Filter shape only (no preamp), so Expert band handles sit on the curve.
        let bands = ParamsBuilder.activeBands(DSPSettings(equalizer: state.equalizer, correction: state.correction))
        let frequencies = ResponseCurve.frequencies(count: 160)
        let magnitudes = ResponseCurve.magnitudes(bands: bands, frequencies: frequencies)
        let active = state.isEnabled
        Canvas { context, size in
            var line = Path()
            for (index, f) in frequencies.enumerated() {
                let y = min(max(scale.y(magnitudes[index]), 1), size.height - 1)
                let point = CGPoint(x: scale.x(f), y: y)
                index == 0 ? line.move(to: point) : line.addLine(to: point)
            }
            var fill = line
            fill.addLine(to: CGPoint(x: size.width, y: scale.y(0)))
            fill.addLine(to: CGPoint(x: 0, y: scale.y(0)))
            fill.closeSubpath()
            let tint: GraphicsContext.Shading = active ? .style(.tint) : .color(.gray)
            context.opacity = 0.2
            context.fill(fill, with: tint)
            context.opacity = 1
            context.stroke(line, with: tint, style: StrokeStyle(lineWidth: 2, lineJoin: .round))
        }
        .allowsHitTesting(false)
    }
}

private struct BandHandlesLayer: View {
    @Environment(AppState.self) private var state
    let scale: GraphScale

    var body: some View {
        ForEach(Array(state.equalizer.expert.bands.enumerated()), id: \.element.id) { index, band in
            BandHandle(index: index, band: band, scale: scale) { updated in
                guard let i = state.equalizer.expert.bands.firstIndex(where: { $0.id == band.id }) else { return }
                state.equalizer.expert.bands[i] = updated.clamped()
            }
        }
    }
}

private struct BandHandle: View {
    let index: Int
    let band: EQBand
    let scale: GraphScale
    let onChange: (EQBand) -> Void

    var body: some View {
        let y = band.type.usesGain ? scale.y(band.gain) : scale.y(0)
        Circle()
            .fill(BandPalette.color(index))
            .overlay(Circle().strokeBorder(.white.opacity(0.85), lineWidth: 1.5))
            .overlay(Text("\(index + 1)").font(.system(size: 8, weight: .bold)).foregroundStyle(.black.opacity(0.75)))
            .frame(width: 15, height: 15)
            .opacity(band.isEnabled ? 1 : 0.35)
            .position(x: scale.x(band.frequency), y: min(max(y, 8), scale.size.height - 8))
            .help(
                "\(band.type.label) · \(Format.frequency(band.frequency)) Hz · \(Format.gain(band.gain)) dB · Q \(String(format: "%.2f", band.q))"
            )
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("eqgraph")).onChanged { drag in
                var updated = band
                updated.frequency = scale.frequency(atX: drag.location.x).rounded()
                if band.type.usesGain {
                    updated.gain = (scale.db(atY: drag.location.y) * 10).rounded() / 10
                }
                onChange(updated)
            })
    }
}
