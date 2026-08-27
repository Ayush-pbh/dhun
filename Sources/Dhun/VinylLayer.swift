import AppKit

/// Color treatments for the record: curated duotones, or tints pulled live
/// from the current album's palette.
enum VinylColorScheme: String, CaseIterable, Hashable {
    case classic
    case ocean
    case sunset
    case emerald
    case violet
    case album

    var label: String {
        switch self {
        case .classic: return "Classic"
        case .ocean: return "Ocean"
        case .sunset: return "Sunset"
        case .emerald: return "Emerald"
        case .violet: return "Violet"
        case .album: return "Album colors"
        }
    }

    func resolve(palette: Palette) -> (primary: NSColor, secondary: NSColor) {
        switch self {
        case .classic:
            return (
                NSColor(calibratedHue: 0.60, saturation: 0.30, brightness: 0.55, alpha: 1),
                NSColor(calibratedHue: 0.05, saturation: 0.28, brightness: 0.50, alpha: 1)
            )
        case .ocean:
            return (
                NSColor(calibratedHue: 0.58, saturation: 0.60, brightness: 0.60, alpha: 1),
                NSColor(calibratedHue: 0.47, saturation: 0.55, brightness: 0.55, alpha: 1)
            )
        case .sunset:
            return (
                NSColor(calibratedHue: 0.06, saturation: 0.70, brightness: 0.62, alpha: 1),
                NSColor(calibratedHue: 0.93, saturation: 0.55, brightness: 0.52, alpha: 1)
            )
        case .emerald:
            return (
                NSColor(calibratedHue: 0.38, saturation: 0.60, brightness: 0.52, alpha: 1),
                NSColor(calibratedHue: 0.50, saturation: 0.50, brightness: 0.50, alpha: 1)
            )
        case .violet:
            return (
                NSColor(calibratedHue: 0.75, saturation: 0.52, brightness: 0.56, alpha: 1),
                NSColor(calibratedHue: 0.90, saturation: 0.45, brightness: 0.50, alpha: 1)
            )
        case .album:
            return (palette.primary, palette.secondary)
        }
    }
}

/// A vinyl record rendered in Core Animation: black grooved disc, the album
/// art as the circular center label, and a spindle dot. Rotation runs at
/// roughly 33⅓ RPM while playing and freezes in place on pause.
final class VinylLayer: CALayer {
    private let discLayer = CALayer()
    private let labelLayer = CALayer()
    private let spindleLayer = CALayer()

    override init() {
        super.init()
        setup()
    }

    override init(layer: Any) {
        super.init(layer: layer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var colorKey: String?

    func setColors(primary: NSColor, secondary: NSColor) {
        let key = "\(primary.description)|\(secondary.description)"
        guard key != colorKey else { return }
        colorKey = key
        discLayer.contents = Self.makeDiscImage(primary: primary, secondary: secondary)
    }

    private func setup() {
        let defaults = VinylColorScheme.classic.resolve(palette: .fallback)
        setColors(primary: defaults.primary, secondary: defaults.secondary)
        discLayer.contentsGravity = .resizeAspect
        addSublayer(discLayer)

        labelLayer.masksToBounds = true
        labelLayer.contentsGravity = .resizeAspectFill
        labelLayer.backgroundColor = NSColor(calibratedWhite: 0.12, alpha: 1).cgColor
        labelLayer.borderColor = NSColor.black.withAlphaComponent(0.6).cgColor
        labelLayer.borderWidth = 1
        addSublayer(labelLayer)

        spindleLayer.backgroundColor = NSColor(calibratedWhite: 0.85, alpha: 1).cgColor
        spindleLayer.borderColor = NSColor.black.cgColor
        spindleLayer.borderWidth = 1
        addSublayer(spindleLayer)
    }

    func setArtwork(_ image: NSImage?) {
        labelLayer.contents = image
    }

    /// Seconds per full revolution (60 / RPM). Changing it mid-spin rebuilds
    /// the animation from the record's current angle so it never jumps.
    var revolutionDuration: CFTimeInterval = 1.8 {
        didSet {
            if abs(revolutionDuration - oldValue) > 0.001 {
                rebuildSpinAnimation()
            }
        }
    }

    func setSpinning(_ spinning: Bool) {
        if animation(forKey: "spin") == nil {
            add(makeSpinAnimation(from: currentAngle()), forKey: "spin")
            if !spinning {
                pauseSpin()
            }
            return
        }
        if spinning, speed == 0 {
            resumeSpin()
        } else if !spinning, speed != 0 {
            pauseSpin()
        }
    }

    private func currentAngle() -> CGFloat {
        (presentation() ?? self).value(forKeyPath: "transform.rotation.z") as? CGFloat ?? 0
    }

    private func makeSpinAnimation(from angle: CGFloat) -> CABasicAnimation {
        let anim = CABasicAnimation(keyPath: "transform.rotation.z")
        anim.fromValue = angle
        anim.toValue = angle - 2 * CGFloat.pi
        anim.duration = revolutionDuration
        anim.repeatCount = .infinity
        anim.isRemovedOnCompletion = false
        return anim
    }

    private func rebuildSpinAnimation() {
        guard animation(forKey: "spin") != nil else { return }
        let angle = currentAngle()
        let wasPaused = speed == 0
        removeAnimation(forKey: "spin")
        speed = 1
        timeOffset = 0
        beginTime = 0
        add(makeSpinAnimation(from: angle), forKey: "spin")
        if wasPaused {
            pauseSpin()
        }
    }

    private func pauseSpin() {
        let now = convertTime(CACurrentMediaTime(), from: nil)
        speed = 0
        timeOffset = now
    }

    private func resumeSpin() {
        let pausedTime = timeOffset
        speed = 1
        timeOffset = 0
        beginTime = 0
        beginTime = convertTime(CACurrentMediaTime(), from: nil) - pausedTime
    }

    override func layoutSublayers() {
        super.layoutSublayers()
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let side = min(bounds.width, bounds.height)
        let discFrame = CGRect(
            x: bounds.midX - side / 2,
            y: bounds.midY - side / 2,
            width: side,
            height: side
        )
        discLayer.frame = discFrame

        let labelSide = side * 0.42
        labelLayer.frame = CGRect(
            x: bounds.midX - labelSide / 2,
            y: bounds.midY - labelSide / 2,
            width: labelSide,
            height: labelSide
        )
        labelLayer.cornerRadius = labelSide / 2

        let spindleSide = max(side * 0.025, 4)
        spindleLayer.frame = CGRect(
            x: bounds.midX - spindleSide / 2,
            y: bounds.midY - spindleSide / 2,
            width: spindleSide,
            height: spindleSide
        )
        spindleLayer.cornerRadius = spindleSide / 2

        CATransaction.commit()
    }

    private static func makeDiscImage(primary: NSColor, secondary: NSColor) -> NSImage {
        let sideLength: CGFloat = 1024
        let p = primary.usingColorSpace(.deviceRGB) ?? primary
        let s = secondary.usingColorSpace(.deviceRGB) ?? secondary
        return NSImage(size: NSSize(width: sideLength, height: sideLength), flipped: false) { rect in
            NSColor(calibratedWhite: 0.06, alpha: 1).setFill()
            NSBezierPath(ovalIn: rect).fill()

            // A faint two-tone wash (one accent per side) so the black
            // isn't flat.
            NSGradient(colors: [
                (p.blended(withFraction: 0.6, of: .black) ?? p).withAlphaComponent(0.40),
                NSColor.clear,
                (s.blended(withFraction: 0.6, of: .black) ?? s).withAlphaComponent(0.35),
            ])?.draw(in: NSBezierPath(ovalIn: rect), angle: 60)

            // Grooves: sparse concentric rings between the label edge and the
            // rim, each a slightly different blend of the two accents.
            let center = NSPoint(x: rect.midX, y: rect.midY)
            var ringIndex = 0
            for radius in stride(from: sideLength * 0.23, through: sideLength * 0.485, by: 14) {
                let mixAmount = 0.5 + 0.5 * sin(Double(ringIndex) * 1.7)
                let mix = p.blended(withFraction: mixAmount, of: s) ?? p
                let darkening = 0.80 + 0.06 * sin(Double(ringIndex) * 2.3)
                (mix.blended(withFraction: darkening, of: .black) ?? mix).setStroke()
                let groove = NSBezierPath(ovalIn: NSRect(
                    x: center.x - radius,
                    y: center.y - radius,
                    width: radius * 2,
                    height: radius * 2
                ))
                groove.lineWidth = 1.4
                groove.stroke()
                ringIndex += 1
            }

            NSColor(calibratedWhite: 1, alpha: 0.16).setStroke()
            let rim = NSBezierPath(ovalIn: rect.insetBy(dx: 2, dy: 2))
            rim.lineWidth = 3
            rim.stroke()
            return true
        }
    }
}
