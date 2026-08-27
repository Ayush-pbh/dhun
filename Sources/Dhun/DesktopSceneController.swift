import AppKit

/// A live scene rendered just above the wallpaper and below the desktop
/// icons: a palette-tinted gradient with a big vinyl record that actually
/// spins while music plays. Because it is a real window (not a wallpaper
/// image), it can animate — something setDesktopImageURL can never do.
final class DesktopSceneController {
    private var window: NSWindow?
    private var sceneView: DesktopSceneView?

    func setEnabled(_ enabled: Bool) {
        if enabled {
            show()
        } else {
            hide()
        }
    }

    func update(artwork: NSImage?, palette: Palette, isPlaying: Bool) {
        guard let sceneView else { return }
        sceneView.vinyl.setArtwork(artwork)
        sceneView.vinyl.setSpinning(isPlaying)
        CATransaction.begin()
        CATransaction.setAnimationDuration(1.0)
        sceneView.gradientLayer.colors = [
            palette.background.cgColor,
            palette.primary.blended(withFraction: 0.55, of: .black)?.cgColor ?? palette.background.cgColor,
        ]
        CATransaction.commit()
    }

    func setSpinning(_ spinning: Bool) {
        sceneView?.vinyl.setSpinning(spinning)
    }

    func setRevolutionDuration(_ duration: CFTimeInterval) {
        sceneView?.vinyl.revolutionDuration = duration
    }

    func setVinylColors(primary: NSColor, secondary: NSColor) {
        sceneView?.vinyl.setColors(primary: primary, secondary: secondary)
    }

    private func show() {
        guard window == nil, let screen = NSScreen.main else { return }
        let w = NSWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        w.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        w.isOpaque = true
        w.backgroundColor = .black
        w.hasShadow = false
        w.ignoresMouseEvents = true
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        let view = DesktopSceneView()
        w.contentView = view
        w.orderFrontRegardless()
        window = w
        sceneView = view
    }

    private func hide() {
        window?.orderOut(nil)
        window = nil
        sceneView = nil
    }
}

private final class DesktopSceneView: NSView {
    let gradientLayer = CAGradientLayer()
    let vinyl = VinylLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        gradientLayer.colors = [
            NSColor(calibratedWhite: 0.09, alpha: 1).cgColor,
            NSColor(calibratedWhite: 0.03, alpha: 1).cgColor,
        ]
        gradientLayer.startPoint = CGPoint(x: 0, y: 1)
        gradientLayer.endPoint = CGPoint(x: 1, y: 0)
        layer?.addSublayer(gradientLayer)
        layer?.addSublayer(vinyl)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradientLayer.frame = bounds
        let side = min(bounds.width, bounds.height) * 0.52
        vinyl.frame = CGRect(
            x: bounds.midX - side / 2,
            y: bounds.midY - side / 2,
            width: side,
            height: side
        )
        CATransaction.commit()
    }
}
