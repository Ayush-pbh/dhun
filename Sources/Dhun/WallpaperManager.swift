import AppKit
import CoreImage

enum WallpaperError: LocalizedError {
    case renderFailed

    var errorDescription: String? {
        switch self {
        case .renderFailed: return "Could not render the wallpaper image."
        }
    }
}

/// Renders the album art into per-screen wallpaper files and applies them
/// with NSWorkspace. Rendering happens off the main thread; the actual
/// desktop swap happens back on it.
final class WallpaperManager {
    private var generation = 0

    private var wallpaperDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Dhun/Wallpapers", isDirectory: true)
    }

    func apply(
        art: NSImage,
        style: WallpaperStyle,
        palette: Palette = .fallback,
        completion: ((Error?) -> Void)? = nil
    ) {
        let specs = NSScreen.screens.map { (size: $0.frame.size, scale: $0.backingScaleFactor) }
        guard !specs.isEmpty, let artCopy = art.copy() as? NSImage else {
            completion?(nil)
            return
        }

        generation += 1
        let gen = generation
        let dir = wallpaperDirectory

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

                var urls: [URL] = []
                for (index, spec) in specs.enumerated() {
                    let rep: NSBitmapImageRep?
                    switch style {
                    case .fillScreen:
                        rep = Self.bitmap(from: artCopy)
                    case .blurredBackdrop:
                        rep = Self.composeBlurred(art: artCopy, sizePt: spec.size, scale: spec.scale)
                    case .paletteGradient:
                        rep = Self.composeGradient(art: artCopy, palette: palette, sizePt: spec.size, scale: spec.scale)
                    }
                    guard let rep,
                          let data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.92]) else {
                        throw WallpaperError.renderFailed
                    }
                    let url = dir.appendingPathComponent("wallpaper-\(index)-\(gen).jpg")
                    try data.write(to: url)
                    urls.append(url)
                }

                DispatchQueue.main.async {
                    guard gen == self.generation else {
                        completion?(nil)
                        return
                    }
                    do {
                        let screens = NSScreen.screens
                        for (index, url) in urls.enumerated() where index < screens.count {
                            try NSWorkspace.shared.setDesktopImageURL(url, for: screens[index], options: [
                                .imageScaling: NSNumber(value: NSImageScaling.scaleProportionallyUpOrDown.rawValue),
                                .allowClipping: true,
                            ])
                        }
                        self.cleanUp(directory: dir, keeping: Set(urls.map(\.lastPathComponent)))
                        completion?(nil)
                    } catch {
                        completion?(error)
                    }
                }
            } catch {
                DispatchQueue.main.async { completion?(error) }
            }
        }
    }

    private func cleanUp(directory: URL, keeping: Set<String>) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for file in files where !keeping.contains(file.lastPathComponent) {
            try? fm.removeItem(at: file)
        }
    }

    private static func bitmap(from image: NSImage) -> NSBitmapImageRep? {
        guard let tiff = image.tiffRepresentation else { return nil }
        return NSBitmapImageRep(data: tiff)
    }

    private static func makeCanvas(pxW: Int, pxH: Int) -> (NSBitmapImageRep, NSGraphicsContext)? {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pxW,
            pixelsHigh: pxH,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        return (rep, context)
    }

    /// Draws the sharp album square centered in the current graphics context,
    /// with a rounded-corner clip and a soft drop shadow.
    private static func drawCenteredArt(_ art: NSImage, in full: CGRect) {
        let side = min(full.width, full.height) * 0.55
        let artRect = CGRect(
            x: full.midX - side / 2,
            y: full.midY - side / 2,
            width: side,
            height: side
        )
        let path = NSBezierPath(roundedRect: artRect, xRadius: side * 0.03, yRadius: side * 0.03)

        // Shadow pass: fill the rounded rect so the shadow renders, then draw
        // the artwork clipped to the same path without a shadow.
        NSGraphicsContext.current?.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.55)
        shadow.shadowBlurRadius = side * 0.09
        shadow.shadowOffset = NSSize(width: 0, height: -side * 0.03)
        shadow.set()
        NSColor.black.setFill()
        path.fill()
        NSGraphicsContext.current?.restoreGraphicsState()

        NSGraphicsContext.current?.saveGraphicsState()
        path.addClip()
        art.draw(in: artRect, from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.current?.restoreGraphicsState()
    }

    /// Screen-sized composition: the artwork blown up, blurred, and slightly
    /// saturated as the backdrop, with the sharp square centered on top.
    private static func composeBlurred(art: NSImage, sizePt: CGSize, scale: CGFloat) -> NSBitmapImageRep? {
        let pxW = Int((sizePt.width * scale).rounded())
        let pxH = Int((sizePt.height * scale).rounded())
        guard pxW > 0, pxH > 0,
              let tiff = art.tiffRepresentation,
              let ciArt = CIImage(data: tiff) else { return nil }

        let px = CGSize(width: CGFloat(pxW), height: CGFloat(pxH))
        let extent = ciArt.extent
        guard extent.width > 0, extent.height > 0 else { return nil }

        let fillScale = max(px.width / extent.width, px.height / extent.height) * 1.15
        var backdrop = ciArt.transformed(by: CGAffineTransform(scaleX: fillScale, y: fillScale))
        let dx = (px.width - backdrop.extent.width) / 2 - backdrop.extent.origin.x
        let dy = (px.height - backdrop.extent.height) / 2 - backdrop.extent.origin.y
        backdrop = backdrop.transformed(by: CGAffineTransform(translationX: dx, y: dy))
        backdrop = backdrop.clampedToExtent()
            .applyingGaussianBlur(sigma: 0.045 * Double(min(px.width, px.height)))
            .cropped(to: CGRect(origin: .zero, size: px))
            .applyingFilter("CIColorControls", parameters: [
                kCIInputBrightnessKey: -0.05,
                kCIInputSaturationKey: 1.2,
            ])

        guard let background = CIContext().createCGImage(backdrop, from: CGRect(origin: .zero, size: px)),
              let (rep, context) = makeCanvas(pxW: pxW, pxH: pxH) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        let full = CGRect(origin: .zero, size: px)
        context.cgContext.draw(background, in: full)
        drawCenteredArt(art, in: full)
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    /// Clean gradient built from the album's own colors with the sharp art
    /// centered — often reads as more intentional than a blur.
    private static func composeGradient(art: NSImage, palette: Palette, sizePt: CGSize, scale: CGFloat) -> NSBitmapImageRep? {
        let pxW = Int((sizePt.width * scale).rounded())
        let pxH = Int((sizePt.height * scale).rounded())
        guard pxW > 0, pxH > 0, let (rep, context) = makeCanvas(pxW: pxW, pxH: pxH) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        let full = CGRect(x: 0, y: 0, width: CGFloat(pxW), height: CGFloat(pxH))

        let colors = [
            palette.background,
            palette.primary.blended(withFraction: 0.45, of: .black) ?? palette.background,
            palette.secondary.blended(withFraction: 0.6, of: .black) ?? palette.background,
        ]
        NSGradient(colors: colors)?.draw(in: full, angle: -60)
        drawCenteredArt(art, in: full)

        NSGraphicsContext.restoreGraphicsState()
        return rep
    }
}
