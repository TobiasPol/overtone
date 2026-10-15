// Renders the app icon into an .iconset folder: swift scripts/make-icon.swift <out.iconset>
import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset")
try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func render(size: Int) -> Data {
    let s = CGFloat(size)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let inset = s * 0.09
    let rect = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let shape = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.225, yRadius: rect.width * 0.225)
    NSGradient(colors: [
        NSColor(red: 0.33, green: 0.38, blue: 1.0, alpha: 1),
        NSColor(red: 0.78, green: 0.30, blue: 0.95, alpha: 1),
    ])!.draw(in: shape, angle: -55)
    let heights: [CGFloat] = [0.34, 0.62, 0.46, 0.74, 0.52]
    let barWidth = rect.width * 0.085
    let gap = (rect.width - barWidth * CGFloat(heights.count)) / CGFloat(heights.count + 1)
    NSColor.white.withAlphaComponent(0.95).setFill()
    for (index, height) in heights.enumerated() {
        let x = rect.minX + gap + CGFloat(index) * (barWidth + gap)
        let h = rect.height * height
        let bar = NSRect(x: x, y: rect.midY - h / 2, width: barWidth, height: h)
        NSBezierPath(roundedRect: bar, xRadius: barWidth / 2, yRadius: barWidth / 2).fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try render(size: base).write(to: output.appendingPathComponent("icon_\(base)x\(base).png"))
    try render(size: base * 2).write(to: output.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
print("Wrote \(output.path)")
