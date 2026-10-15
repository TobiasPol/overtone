import AppKit
import SwiftUI

/// Overtone's mark: an "O" ring crossed by a sound wave that swells in the
/// middle and fades into the centre line at both ends.
///
/// One definition serves the menu bar template icon, the in-app glyph and the
/// app icon, so every size stays consistent.
struct LogoMark: Shape {
    /// Stroke width as a fraction of the mark's size.
    var weight: CGFloat = 0.09

    func path(in rect: CGRect) -> Path {
        let size = min(rect.width, rect.height)
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        let radius = size * 0.35
        var path = Path()
        path.addEllipse(in: CGRect(
            x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2
        ))
        path.addPath(wave(centre: centre, size: size))
        return path.strokedPath(StrokeStyle(lineWidth: size * weight, lineCap: .round, lineJoin: .round))
    }

    /// One sine period under a sin(πt) envelope, spanning almost the full width.
    private func wave(centre: CGPoint, size: CGFloat) -> Path {
        let start = centre.x - size * 0.45
        let width = size * 0.9
        let amplitude = size * 0.2
        var path = Path()
        let steps = 64
        for step in 0...steps {
            let t = CGFloat(step) / CGFloat(steps)
            let y = centre.y - amplitude * sin(2 * .pi * t) * sin(.pi * t)
            let point = CGPoint(x: start + width * t, y: y)
            step == 0 ? path.move(to: point) : path.addLine(to: point)
        }
        return path
    }
}

/// Menu bar icon images (template, so macOS tints them for light/dark/selected).
@MainActor
enum StatusIcon {
    static let pointSize = NSSize(width: 18, height: 18)

    /// - Parameter attention: adds a small badge dot when processing has a problem.
    static func image(attention: Bool = false) -> NSImage {
        let image = NSImage(size: pointSize, flipped: true) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            let markRect = attention ? rect.insetBy(dx: 1.2, dy: 1.2).offsetBy(dx: -0.8, dy: 0.8) : rect.insetBy(dx: 0.5, dy: 0.5)
            context.addPath(LogoMark(weight: 0.1).path(in: markRect).cgPath)
            context.setFillColor(NSColor.black.cgColor)
            context.fillPath()
            if attention { drawBadge(in: rect, context: context) }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = attention ? "Overtone (needs attention)" : "Overtone"
        return image
    }

    private static func drawBadge(in rect: CGRect, context: CGContext) {
        let dot = CGRect(x: rect.maxX - 5.8, y: rect.minY, width: 5.8, height: 5.8)
        context.setBlendMode(.clear)
        context.fillEllipse(in: dot.insetBy(dx: -1.4, dy: -1.4))
        context.setBlendMode(.normal)
        context.fillEllipse(in: dot)
    }
}

/// The app icon artwork: the white mark on a near-black tile.
struct AppIconArtwork: View {
    var size: CGFloat

    var body: some View {
        let tile = size * 0.805 // macOS icon grid: 824 of 1024
        let shape = RoundedRectangle(cornerRadius: tile * 0.225, style: .continuous)
        ZStack {
            shape
                .fill(LinearGradient(
                    colors: [Color(white: 0.17), Color(white: 0.05)], startPoint: .top, endPoint: .bottom
                ))
                .overlay(shape.strokeBorder(Color.white.opacity(0.12), lineWidth: max(1, size * 0.004)))
                .frame(width: tile, height: tile)
                .shadow(color: .black.opacity(size > 64 ? 0.3 : 0), radius: size * 0.018, y: size * 0.012)
            LogoMark(weight: 0.085)
                .fill(.white)
                .frame(width: tile * 0.62, height: tile * 0.62)
        }
        .frame(width: size, height: size)
    }
}
