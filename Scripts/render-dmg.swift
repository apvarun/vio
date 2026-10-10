#!/usr/bin/env swift
// Editable vector artwork. Run: make dmg-artwork
import AppKit

let width = 720, height = 460
guard let appIcon = NSImage(contentsOfFile: "build/Vio.icns") else {
    fatalError("Compile Resources/vio.icon first with make app-icon.")
}
func render(scale: Int) -> NSBitmapImageRep {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width * scale, pixelsHigh: height * scale,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let transform = NSAffineTransform()
    transform.scale(by: CGFloat(scale))
    transform.concat()
    func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: r, green: g, blue: b, alpha: a)
    }
    color(0.055, 0.085, 0.09).setFill()
    NSBezierPath(rect: NSRect(x: 0, y: 0, width: width, height: height)).fill()
    // Waveform sits behind the header, leaving the install controls uncluttered.
    color(0.20, 0.78, 0.69, 0.13).setStroke()
    for i in 0..<65 {
        let x = CGFloat(36 + i * 10)
        let amplitude = CGFloat(8 + 38 * abs(sin(Double(i) * 0.43)) * exp(-pow((Double(i) - 32) / 21, 2)))
        let line = NSBezierPath()
        line.move(to: NSPoint(x: x, y: 355 - amplitude))
        line.line(to: NSPoint(x: x, y: 355 + amplitude))
        line.lineWidth = 3
        line.lineCapStyle = .round
        line.stroke()
    }
    func text(_ value: String, _ size: CGFloat, _ weight: NSFont.Weight, _ y: CGFloat, _ ink: NSColor) {
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: ink]
        let label = NSAttributedString(string: value, attributes: attributes)
        label.draw(at: NSPoint(x: (CGFloat(width) - label.size().width) / 2, y: y))
    }
    let title = NSAttributedString(string: "Vio", attributes: [
        .font: NSFont.systemFont(ofSize: 42, weight: .semibold),
        .foregroundColor: color(0.91, 0.98, 0.96)
    ])
    let headerX = (CGFloat(width) - 48 - 12 - title.size().width) / 2
    appIcon.draw(in: NSRect(x: headerX, y: 344, width: 48, height: 48))
    title.draw(at: NSPoint(x: headerX + 60, y: 345))
    text("Your voice. On your Mac.", 15, .regular, 317, color(0.57, 0.73, 0.70))
    // Finder renders icon labels in dark text. These light pads provide contrast.
    color(0.79, 0.89, 0.86).setFill()
    for x in [CGFloat(140), CGFloat(470)] {
        NSBezierPath(roundedRect: NSRect(x: x, y: 144, width: 110, height: 28), xRadius: 14, yRadius: 14).fill()
    }
    color(0.28, 0.82, 0.72).setStroke()
    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: 325, y: 230)); arrow.line(to: NSPoint(x: 395, y: 230))
    arrow.move(to: NSPoint(x: 384, y: 241)); arrow.line(to: NSPoint(x: 395, y: 230)); arrow.line(to: NSPoint(x: 384, y: 219))
    arrow.lineWidth = 2.5; arrow.lineCapStyle = .round; arrow.lineJoinStyle = .round; arrow.stroke()
    text("Drag to Applications to install", 16, .medium, 79, color(0.84, 0.94, 0.91))
    text("APPLE SILICON  /  macOS 26+", 10, .medium, 39, color(0.43, 0.60, 0.57))
    NSGraphicsContext.restoreGraphicsState()
    bitmap.size = NSSize(width: width, height: height)
    return bitmap
}

let output = CommandLine.arguments.dropFirst().first ?? "Resources/DMG/background.png"
let retina = render(scale: 2)
try retina.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
// Finder selects the appropriate representation without changing the 720 × 460 layout.
let tiffOutput = URL(fileURLWithPath: output).deletingPathExtension().appendingPathExtension("tiff")
try NSBitmapImageRep.representationOfImageReps(in: [render(scale: 1), retina], using: .tiff,
    properties: [:])!.write(to: tiffOutput)
