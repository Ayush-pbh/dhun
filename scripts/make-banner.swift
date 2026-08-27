// Renders the GitHub hero banner (docs/banner.png, 1920×960): wordmark and
// tagline on the left, the vinyl on the right, on a dark stage.
//
// Run from the project root:  swift scripts/make-banner.swift

import AppKit

let width: CGFloat = 1920
let height: CGFloat = 960

func devanagariFont(size: CGFloat) -> NSFont {
    NSFont(name: "KohinoorDevanagari-Bold", size: size)
        ?? NSFont(name: "DevanagariMT-Bold", size: size)
        ?? NSFont.systemFont(ofSize: size, weight: .bold)
}

let banner = NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
    // Stage
    NSGradient(colors: [
        NSColor(calibratedHue: 0.08, saturation: 0.35, brightness: 0.13, alpha: 1),
        NSColor(calibratedWhite: 0.03, alpha: 1),
    ])?.draw(in: rect, angle: -70)

    // Faint amber pool behind the record
    let glowCenter = NSPoint(x: width * 0.72, y: height * 0.5)
    let glowRadius: CGFloat = 520
    let glowRect = NSRect(
        x: glowCenter.x - glowRadius,
        y: glowCenter.y - glowRadius,
        width: glowRadius * 2,
        height: glowRadius * 2
    )
    NSGradient(
        starting: NSColor(calibratedHue: 0.08, saturation: 0.85, brightness: 0.55, alpha: 0.28),
        ending: NSColor.clear
    )?.draw(in: NSBezierPath(ovalIn: glowRect), relativeCenterPosition: .zero)

    // Record
    let discRadius: CGFloat = 380
    let center = glowCenter
    let discRect = NSRect(
        x: center.x - discRadius,
        y: center.y - discRadius,
        width: discRadius * 2,
        height: discRadius * 2
    )
    NSColor(calibratedWhite: 0.06, alpha: 1).setFill()
    NSBezierPath(ovalIn: discRect).fill()
    NSGradient(colors: [
        NSColor(calibratedHue: 0.06, saturation: 0.55, brightness: 0.22, alpha: 0.45),
        NSColor.clear,
        NSColor(calibratedHue: 0.93, saturation: 0.45, brightness: 0.18, alpha: 0.40),
    ])?.draw(in: NSBezierPath(ovalIn: discRect), angle: 60)

    var ringIndex = 0
    for radius in stride(from: discRadius * 0.52, through: discRadius * 0.94, by: discRadius * 0.05) {
        let brightness = 0.16 + 0.05 * sin(Double(ringIndex) * 2.3)
        NSColor(calibratedHue: 0.06, saturation: 0.30, brightness: brightness, alpha: 0.9).setStroke()
        let groove = NSBezierPath(ovalIn: NSRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        ))
        groove.lineWidth = 3
        groove.stroke()
        ringIndex += 1
    }
    NSColor(calibratedWhite: 1, alpha: 0.16).setStroke()
    let rim = NSBezierPath(ovalIn: discRect.insetBy(dx: 2, dy: 2))
    rim.lineWidth = 4
    rim.stroke()

    // Label
    let labelSide = discRadius * 2 * 0.46
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

    let labelMark = NSAttributedString(string: "धुन", attributes: [
        .font: devanagariFont(size: labelSide * 0.34),
        .foregroundColor: NSColor.white,
    ])
    let labelBounds = labelMark.boundingRect(with: labelRect.size, options: [.usesLineFragmentOrigin])
    labelMark.draw(with: NSRect(
        x: labelRect.midX - labelBounds.width / 2,
        y: labelRect.midY - labelBounds.height / 2,
        width: labelBounds.width,
        height: labelBounds.height
    ), options: [.usesLineFragmentOrigin])

    // Wordmark + tagline
    let textX: CGFloat = 150
    let wordmark = NSAttributedString(string: "धुन", attributes: [
        .font: devanagariFont(size: 210),
        .foregroundColor: NSColor.white,
    ])
    wordmark.draw(at: NSPoint(x: textX, y: height * 0.52))

    let name = NSAttributedString(string: "Dhun", attributes: [
        .font: NSFont.systemFont(ofSize: 64, weight: .semibold),
        .foregroundColor: NSColor(calibratedHue: 0.09, saturation: 0.75, brightness: 0.95, alpha: 1),
    ])
    name.draw(at: NSPoint(x: textX + 6, y: height * 0.40))

    let tagline = NSAttributedString(
        string: "Whatever Spotify is playing,\nliving on your desktop as art.",
        attributes: [
            .font: NSFont.systemFont(ofSize: 40, weight: .regular),
            .foregroundColor: NSColor(calibratedWhite: 1, alpha: 0.75),
        ]
    )
    tagline.draw(with: NSRect(x: textX + 6, y: height * 0.17, width: 760, height: 160),
                 options: [.usesLineFragmentOrigin])

    return true
}

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(width),
    pixelsHigh: Int(height),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
), let context = NSGraphicsContext(bitmapImageRep: rep) else {
    fatalError("Could not create banner bitmap")
}
rep.size = NSSize(width: width, height: height)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
banner.draw(in: NSRect(x: 0, y: 0, width: width, height: height), from: .zero, operation: .copy, fraction: 1)
NSGraphicsContext.restoreGraphicsState()
guard let data = rep.representation(using: .png, properties: [:]) else {
    fatalError("Could not encode banner PNG")
}
try data.write(to: URL(fileURLWithPath: "docs/banner.png"))
print("Wrote docs/banner.png")
