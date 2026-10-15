import SwiftUI

/// Rotary control: drag vertically to turn, double-click to reset.
struct Knob: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var defaultValue = 0.0
    var size: CGFloat = 68
    var step = 0.5

    @State private var dragOrigin: Double?

    private var span: Double { range.upperBound - range.lowerBound }
    private func fraction(_ v: Double) -> Double { (v - range.lowerBound) / span }
    /// Trim position on a circle rotated so 0 sits at six o'clock.
    private func trim(_ v: Double) -> CGFloat { CGFloat(0.125 + fraction(v) * 0.75) }

    var body: some View {
        let from = min(trim(defaultValue), trim(value))
        let to = max(trim(defaultValue), trim(value))
        ZStack {
            Circle().fill(Color.primary.opacity(0.06))
            Circle()
                .trim(from: 0.125, to: 0.875)
                .stroke(Color.primary.opacity(0.12), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(90))
                .padding(3)
            Circle()
                .trim(from: from, to: to)
                .stroke(.tint, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(90))
                .padding(3)
            Capsule()
                .fill(Color.primary.opacity(0.8))
                .frame(width: 3, height: size * 0.2)
                .offset(y: -size * 0.22)
                .rotationEffect(.degrees(-135 + fraction(value) * 270))
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .gesture(dragGesture)
        .simultaneousGesture(TapGesture(count: 2).onEnded { value = defaultValue })
        .accessibilityElement()
        .accessibilityValue(Text(String(format: "%.1f", value)))
        .accessibilityAdjustableAction { direction in
            value = (value + (direction == .increment ? step : -step)).clamped(to: range)
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { drag in
                let origin = dragOrigin ?? value
                dragOrigin = origin
                let raw = origin - Double(drag.translation.height) / 160 * span
                value = ((raw / step).rounded() * step).clamped(to: range)
            }
            .onEnded { _ in dragOrigin = nil }
    }
}

/// Vertical fader for graphic EQ bands: drag anywhere on the track, double-click to reset.
struct VerticalSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var defaultValue = 0.0
    var step = 0.1

    private let thumb: CGFloat = 14

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let yValue = y(for: value, height: h)
            let yCentre = y(for: defaultValue, height: h)
            ZStack {
                Capsule().fill(Color.primary.opacity(0.1)).frame(width: 4, height: h - thumb).position(x: w / 2, y: h / 2)
                Capsule().fill(.tint)
                    .frame(width: 4, height: abs(yValue - yCentre))
                    .position(x: w / 2, y: (yValue + yCentre) / 2)
                Circle()
                    .fill(.white)
                    .shadow(color: .black.opacity(0.35), radius: 1.5, y: 0.5)
                    .frame(width: thumb, height: thumb)
                    .position(x: w / 2, y: yValue)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                let f = 1 - (drag.location.y - thumb / 2) / (h - thumb)
                let raw = range.lowerBound + Double(f) * (range.upperBound - range.lowerBound)
                value = ((raw / step).rounded() * step).clamped(to: range)
            })
            .simultaneousGesture(TapGesture(count: 2).onEnded { value = defaultValue })
        }
    }

    private func y(for v: Double, height: CGFloat) -> CGFloat {
        let f = (v - range.lowerBound) / (range.upperBound - range.lowerBound)
        return thumb / 2 + (1 - CGFloat(f)) * (height - thumb)
    }
}
