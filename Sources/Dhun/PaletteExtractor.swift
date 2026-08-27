import AppKit

struct Palette: Equatable {
    var primary: NSColor
    var secondary: NSColor
    var background: NSColor

    static let fallback = Palette(
        primary: NSColor(deviceRed: 0.55, green: 0.55, blue: 0.58, alpha: 1),
        secondary: NSColor(deviceRed: 0.35, green: 0.35, blue: 0.38, alpha: 1),
        background: NSColor(deviceRed: 0.09, green: 0.09, blue: 0.11, alpha: 1)
    )
}

/// Cheap dominant-color extraction: downsample to 32×32, quantize to a
/// 4-bit-per-channel histogram, and score clusters by frequency × vibrancy.
enum PaletteExtractor {
    static func extract(from image: NSImage) -> Palette {
        let side = 32
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let context = CGContext(
                data: nil,
                width: side,
                height: side,
                bitsPerComponent: 8,
                bytesPerRow: side * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return .fallback }

        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
        guard let data = context.data else { return .fallback }
        let pixels = data.bindMemory(to: UInt8.self, capacity: side * side * 4)

        struct Bucket {
            var r = 0.0, g = 0.0, b = 0.0, count = 0.0
        }
        var buckets: [Int: Bucket] = [:]
        for i in 0..<(side * side) {
            let r = Double(pixels[i * 4]) / 255
            let g = Double(pixels[i * 4 + 1]) / 255
            let b = Double(pixels[i * 4 + 2]) / 255
            let key = (Int(r * 15) << 8) | (Int(g * 15) << 4) | Int(b * 15)
            var bucket = buckets[key, default: Bucket()]
            bucket.r += r
            bucket.g += g
            bucket.b += b
            bucket.count += 1
            buckets[key] = bucket
        }

        func score(_ bucket: Bucket) -> Double {
            let r = bucket.r / bucket.count
            let g = bucket.g / bucket.count
            let b = bucket.b / bucket.count
            let maxC = max(r, g, b)
            let minC = min(r, g, b)
            let saturation = maxC == 0 ? 0 : (maxC - minC) / maxC
            // Near-black and near-white clusters make poor accent colors.
            let usable = (0.12...0.92).contains(maxC) ? 1.0 : 0.15
            return bucket.count * (0.1 + saturation) * usable
        }

        func color(_ bucket: Bucket) -> NSColor {
            NSColor(
                deviceRed: CGFloat(bucket.r / bucket.count),
                green: CGFloat(bucket.g / bucket.count),
                blue: CGFloat(bucket.b / bucket.count),
                alpha: 1
            )
        }

        let sorted = buckets.values.sorted { score($0) > score($1) }
        guard let first = sorted.first, first.count > 0 else { return .fallback }

        let primary = color(first)
        var secondary = primary.blended(withFraction: 0.4, of: .white) ?? primary
        for bucket in sorted.dropFirst() {
            let candidate = color(bucket)
            if distance(candidate, primary) > 0.25 {
                secondary = candidate
                break
            }
        }
        let background = primary.blended(withFraction: 0.78, of: .black) ?? .black
        return Palette(primary: primary, secondary: secondary, background: background)
    }

    private static func distance(_ a: NSColor, _ b: NSColor) -> CGFloat {
        let dr = a.redComponent - b.redComponent
        let dg = a.greenComponent - b.greenComponent
        let db = a.blueComponent - b.blueComponent
        return (dr * dr + dg * dg + db * db).squareRoot()
    }
}
