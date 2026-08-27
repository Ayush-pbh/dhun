// Renders the Dhun app icon: a vinyl record with a warm amber label carrying
// the Devanagari wordmark, on a dark rounded-rect plate. Writes an .iconset
// to build/AppIcon.iconset (convert with `iconutil -c icns`).
//
// Run from the project root:  swift scripts/make-icon.swift

import AppKit

let canvas: CGFloat = 1024

let icon = NSImage(size: NSSize(width: canvas, height: canvas), flipped: false) { rect in
    // macOS icon grid: content plate is ~824pt of the 1024 canvas.
    let plateRect = rect.insetBy(dx: 100, dy: 100)
    let plate = NSBezierPath(roundedRect: plateRect, xRadius: 185, yRadius: 185)
    NSGradient(colors: [
        NSColor(calibratedHue: 0.08, saturation: 0.30, brightness: 0.17, alpha: 1),
        NSColor(calibratedWhite: 0.04, alpha: 1),
    ])?.draw(in: plate, angle: -90)

    // Disc
    let discRect = plateRect.insetBy(dx: 78, dy: 78)
    NSColor(calibratedWhite: 0.07, alpha: 1).setFill()
    NSBezierPath(ovalIn: discRect).fill()

    // Two-tone sheen, sunset flavored
    NSGradient(colors: [
        NSColor(calibratedHue: 0.06, saturation: 0.55, brightness: 0.22, alpha: 0.45),
        NSColor.clear,
        NSColor(calibratedHue: 0.93, saturation: 0.45, brightness: 0.18, alpha: 0.40),
    ])?.draw(in: NSBezierPath(ovalIn: discRect), angle: 60)

    // Sparse grooves
    let center = NSPoint(x: discRect.midX, y: discRect.midY)
    let discRadius = discRect.width / 2
    var ringIndex = 0
    for radius in stride(from: discRadius * 0.52, through: discRadius * 0.94, by: discRadius * 0.055) {
        let brightness = 0.16 + 0.05 * sin(Double(ringIndex) * 2.3)
        NSColor(calibratedHue: 0.06, saturation: 0.30, brightness: brightness, alpha: 0.9).setStroke()
        let groove = NSBezierPath(ovalIn: NSRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        ))
        groove.lineWidth = discRadius * 0.008
        groove.stroke()
        ringIndex += 1
    }

    // Rim highlight
    NSColor(calibratedWhite: 1, alpha: 0.18).setStroke()
    let rim = NSBezierPath(ovalIn: discRect.insetBy(dx: 3, dy: 3))
    rim.lineWidth = 5
    rim.stroke()

    // Amber label
    let labelSide = discRect.width * 0.46
    let labelRect = NSRect(
        x: center.x - labelSide / 2,
        y: center.y - labelSide / 2,
        width: labelSide,
        height: labelSide
    )
    NSGradient(colors: [
        NSColor(calibratedHue: 0.10, saturation: 0.80, brightness: 0.95, alpha: 1),
        NSColor(calibratedHue: 0.07, saturation: 0.90, brightness: 0.78, alpha: 1),
    ])?.draw(in: NSBezierPath(ovalIn: labelRect), angle: -90)
    NSColor.black.withAlphaComponent(0.35).setStroke()
    let labelEdge = NSBezierPath(ovalIn: labelRect)
    labelEdge.lineWidth = 3
    labelEdge.stroke()

    // Wordmark — use an explicit Devanagari face so the conjuncts shape
    // correctly (the system-font fallback mangles them in offline drawing).
    let fontSize = labelSide * 0.34
    let devanagariFont = NSFont(name: "KohinoorDevanagari-Bold", size: fontSize)
        ?? NSFont(name: "DevanagariMT-Bold", size: fontSize)
        ?? NSFont.systemFont(ofSize: fontSize, weight: .bold)
    let wordmark = NSAttributedString(string: "धुन", attributes: [
        .font: devanagariFont,
        .foregroundColor: NSColor.white,
    ])
    let textBounds = wordmark.boundingRect(with: labelRect.size, options: [.usesLineFragmentOrigin])
    wordmark.draw(with: NSRect(
        x: labelRect.midX - textBounds.width / 2,
        y: labelRect.midY - textBounds.height / 2,
        width: textBounds.width,
        height: textBounds.height
    ), options: [.usesLineFragmentOrigin])

    return true
}

func writePNG(_ pixels: Int, to url: URL) throws {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: rep) else {
        fatalError("Could not create bitmap for \(pixels)px")
    }
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    icon.draw(
        in: NSRect(x: 0, y: 0, width: pixels, height: pixels),
        from: .zero,
        operation: .copy,
        fraction: 1
    )
    NSGraphicsContext.restoreGraphicsState()
    guard let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("Could not encode PNG for \(pixels)px")
    }
    try data.write(to: url)
}

let iconsetURL = URL(fileURLWithPath: "build/AppIcon.iconset", isDirectory: true)
try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

let entries: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]
for (name, pixels) in entries {
    try writePNG(pixels, to: iconsetURL.appendingPathComponent(name))
}
print("Wrote \(iconsetURL.path)")
