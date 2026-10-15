import AppKit
import SwiftUI

/// Developer tool: `Overtone --render-artwork <folder>` writes the app icon set,
/// a README logo and a menu bar preview, all drawn from `LogoMark`.
@MainActor
enum ArtworkRenderer {
    static func runIfRequested() -> Bool {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "--render-artwork"), index + 1 < args.count else { return false }
        render(to: URL(fileURLWithPath: args[index + 1]))
        return true
    }

    private static func render(to folder: URL) {
        let iconset = folder.appendingPathComponent("AppIcon.iconset")
        try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
        for base in [16, 32, 128, 256, 512] {
            write(AppIconArtwork(size: CGFloat(base)), to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
            write(
                AppIconArtwork(size: CGFloat(base)),
                scale: 2,
                to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png")
            )
        }
        write(AppIconArtwork(size: 256), scale: 2, to: folder.appendingPathComponent("logo.png"))
        write(MenuBarPreview(), scale: 3, to: folder.appendingPathComponent("menubar.png"))
        print("Artwork written to \(folder.path)")
    }

    private static func write(_ view: some View, scale: CGFloat = 1, to url: URL) {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        guard let image = renderer.cgImage else { return }
        let rep = NSBitmapImageRep(cgImage: image)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}

/// How the template icon looks in a light and a dark menu bar, normal and with a problem badge.
private struct MenuBarPreview: View {
    var body: some View {
        HStack(spacing: 0) {
            bar(background: Color(white: 0.93), foreground: .black)
            bar(background: Color(white: 0.16), foreground: .white)
        }
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private func bar(background: Color, foreground: Color) -> some View {
        HStack(spacing: 14) {
            icon(attention: false, color: foreground)
            icon(attention: true, color: foreground)
        }
        .padding(.horizontal, 14)
        .frame(height: 28)
        .background(background)
    }

    private func icon(attention: Bool, color: Color) -> some View {
        Image(nsImage: StatusIcon.image(attention: attention))
            .renderingMode(.template)
            .foregroundStyle(color)
            .frame(width: 18, height: 18)
    }
}
