import AppKit

/// Borderless windows refuse key/main status by default; the art window
/// accepts both so menu shortcuts work while it is frontmost.
final class ArtWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// The square itself. Depending on the persona it renders either the plain
/// artwork or a spinning vinyl record, with optional progress indicator and
/// hover playback controls. Dragging is handled manually so releases can
/// carry momentum when physics is enabled.
final class ArtView: NSView {
    var onDoubleClick: (() -> Void)?
    var menuProvider: (() -> NSMenu?)?
    var onPlayPause: (() -> Void)?
    var onNext: (() -> Void)?
    var onPrevious: (() -> Void)?
    var onVolumeScroll: ((Double) -> Void)?

    var physicsEnabled = false

    var hoverControlsEnabled = false {
        didSet {
            if !hoverControlsEnabled { setControlsVisible(false) }
        }
    }

    var persona: ArtPersona = .plainSquare {
        didSet {
            if persona != oldValue { applyPersona() }
        }
    }

    var cornerRadius: CGFloat = 0 {
        didSet {
            if persona == .plainSquare { layer?.cornerRadius = cornerRadius }
        }
    }

    var showsProgress = false {
        didSet { progressLayer.isHidden = !showsProgress }
    }

    var vinylRevolutionDuration: CFTimeInterval = 1.8 {
        didSet { vinylLayer.revolutionDuration = vinylRevolutionDuration }
    }

    func setVinylColors(primary: NSColor, secondary: NSColor) {
        vinylLayer.setColors(primary: primary, secondary: secondary)
    }

    private(set) var image: NSImage?
    private let artLayer = CALayer()
    private let vinylLayer = VinylLayer()
    private let progressLayer = CAShapeLayer()
    private var isPlaying = false

    private var controlsView: NSView!
    private var playPauseButton: NSButton!
    private var controlsVisible = false

    private var dragStartMouse = NSPoint.zero
    private var dragStartOrigin = NSPoint.zero
    private var dragSamples: [(time: TimeInterval, point: NSPoint)] = []
    private var momentumTimer: Timer?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true

        artLayer.contentsGravity = .resizeAspectFill
        layer?.addSublayer(artLayer)

        vinylLayer.isHidden = true
        layer?.addSublayer(vinylLayer)

        progressLayer.fillColor = NSColor.clear.cgColor
        progressLayer.strokeColor = NSColor.white.withAlphaComponent(0.85).cgColor
        progressLayer.lineWidth = 3
        progressLayer.lineCap = .round
        progressLayer.strokeEnd = 0
        progressLayer.isHidden = true
        layer?.addSublayer(progressLayer)

        buildControls()
        applyPersona()
        setImage(nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Content

    func setImage(_ newImage: NSImage?) {
        image = newImage
        let transition = CATransition()
        transition.duration = 0.35
        transition.type = .fade
        artLayer.add(transition, forKey: "fade")
        artLayer.contents = newImage ?? Self.placeholder
        vinylLayer.setArtwork(newImage)
    }

    func setPlaying(_ playing: Bool) {
        isPlaying = playing
        if persona == .vinyl {
            vinylLayer.setSpinning(playing)
        }
        playPauseButton.image = Self.symbol(playing ? "pause.fill" : "play.fill", size: 15)
    }

    func setProgress(_ progress: CGFloat) {
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.3)
        progressLayer.strokeEnd = max(0, min(1, progress))
        CATransaction.commit()
    }

    private func applyPersona() {
        switch persona {
        case .plainSquare:
            artLayer.isHidden = false
            vinylLayer.isHidden = true
            vinylLayer.setSpinning(false)
            layer?.backgroundColor = NSColor.black.cgColor
            layer?.cornerRadius = cornerRadius
        case .vinyl:
            artLayer.isHidden = true
            vinylLayer.isHidden = false
            vinylLayer.setSpinning(isPlaying)
            layer?.backgroundColor = NSColor.clear.cgColor
            layer?.cornerRadius = 0
        }
        needsLayout = true
        window?.invalidateShadow()
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        artLayer.frame = bounds
        vinylLayer.frame = bounds
        progressLayer.frame = bounds
        updateProgressPath()
        CATransaction.commit()
        controlsView.frame = NSRect(x: (bounds.width - 156) / 2, y: 14, width: 156, height: 42)
    }

    private func updateProgressPath() {
        let path = CGMutablePath()
        switch persona {
        case .vinyl:
            let side = min(bounds.width, bounds.height)
            let radius = side / 2 - 4
            if radius > 0 {
                path.addArc(
                    center: CGPoint(x: bounds.midX, y: bounds.midY),
                    radius: radius,
                    startAngle: CGFloat.pi / 2,
                    endAngle: CGFloat.pi / 2 - 2 * CGFloat.pi,
                    clockwise: true
                )
            }
        case .plainSquare:
            path.move(to: CGPoint(x: 6, y: 3))
            path.addLine(to: CGPoint(x: bounds.width - 6, y: 3))
        }
        progressLayer.path = path
    }

    // MARK: - Hover controls

    private func buildControls() {
        let previous = makeControlButton("backward.fill", action: #selector(previousPressed))
        playPauseButton = makeControlButton("play.fill", action: #selector(playPausePressed))
        let next = makeControlButton("forward.fill", action: #selector(nextPressed))

        let stack = NSStackView(views: [previous, playPauseButton, next])
        stack.orientation = .horizontal
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false

        let container: NSView
        if #available(macOS 26.0, *) {
            // Liquid Glass: refracts the artwork behind the pill.
            let glass = NSGlassEffectView()
            glass.cornerRadius = 21
            glass.tintColor = NSColor.black.withAlphaComponent(0.2)
            let wrapper = NSView()
            wrapper.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.centerXAnchor.constraint(equalTo: wrapper.centerXAnchor),
                stack.centerYAnchor.constraint(equalTo: wrapper.centerYAnchor),
            ])
            glass.contentView = wrapper
            container = glass
        } else {
            let effect = NSVisualEffectView()
            effect.material = .hudWindow
            effect.blendingMode = .withinWindow
            effect.state = .active
            effect.wantsLayer = true
            effect.layer?.cornerRadius = 21
            effect.layer?.masksToBounds = true
            effect.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.centerXAnchor.constraint(equalTo: effect.centerXAnchor),
                stack.centerYAnchor.constraint(equalTo: effect.centerYAnchor),
            ])
            container = effect
        }
        container.alphaValue = 0
        addSubview(container)
        controlsView = container
    }

    private func makeControlButton(_ symbolName: String, action: Selector) -> NSButton {
        let button = NSButton(image: Self.symbol(symbolName, size: 15), target: self, action: action)
        button.isBordered = false
        button.contentTintColor = .white
        button.setButtonType(.momentaryChange)
        return button
    }

    private static func symbol(_ name: String, size: CGFloat) -> NSImage {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: name) ?? NSImage()
        return image.withSymbolConfiguration(.init(pointSize: size, weight: .semibold)) ?? image
    }

    @objc private func playPausePressed() { onPlayPause?() }
    @objc private func nextPressed() { onNext?() }
    @objc private func previousPressed() { onPrevious?() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        if hoverControlsEnabled { setControlsVisible(true) }
    }

    override func mouseExited(with event: NSEvent) {
        setControlsVisible(false)
    }

    private func setControlsVisible(_ visible: Bool) {
        guard controlsVisible != visible, controlsView != nil else { return }
        controlsVisible = visible
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            controlsView.animator().alphaValue = visible ? 1 : 0
        }
    }

    // MARK: - Dragging, physics, scroll

    override func mouseDown(with event: NSEvent) {
        momentumTimer?.invalidate()
        if event.clickCount == 2 {
            dragSamples = []
            onDoubleClick?()
            return
        }
        dragStartMouse = NSEvent.mouseLocation
        dragStartOrigin = window?.frame.origin ?? .zero
        dragSamples = [(ProcessInfo.processInfo.systemUptime, dragStartMouse)]
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window else { return }
        let mouse = NSEvent.mouseLocation
        window.setFrameOrigin(NSPoint(
            x: dragStartOrigin.x + (mouse.x - dragStartMouse.x),
            y: dragStartOrigin.y + (mouse.y - dragStartMouse.y)
        ))
        dragSamples.append((ProcessInfo.processInfo.systemUptime, mouse))
        if dragSamples.count > 6 { dragSamples.removeFirst() }
    }

    override func mouseUp(with event: NSEvent) {
        guard physicsEnabled, dragSamples.count >= 2,
              let first = dragSamples.first, let last = dragSamples.last else { return }
        let dt = last.time - first.time
        guard dt > 0.001 else { return }
        let velocity = NSPoint(
            x: (last.point.x - first.point.x) / dt,
            y: (last.point.y - first.point.y) / dt
        )
        guard velocity.x.magnitude + velocity.y.magnitude > 250 else { return }
        startMomentum(velocity: velocity)
    }

    private func startMomentum(velocity: NSPoint) {
        var v = velocity
        momentumTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            guard let window = self?.window else {
                timer.invalidate()
                return
            }
            var origin = window.frame.origin
            origin.x += v.x / 60
            origin.y += v.y / 60
            v.x *= 0.94
            v.y *= 0.94

            if let screen = window.screen ?? NSScreen.main {
                let limit = screen.visibleFrame
                if origin.x < limit.minX {
                    origin.x = limit.minX
                    v.x = -v.x * 0.5
                }
                if origin.x + window.frame.width > limit.maxX {
                    origin.x = limit.maxX - window.frame.width
                    v.x = -v.x * 0.5
                }
                if origin.y < limit.minY {
                    origin.y = limit.minY
                    v.y = -v.y * 0.5
                }
                if origin.y + window.frame.height > limit.maxY {
                    origin.y = limit.maxY - window.frame.height
                    v.y = -v.y * 0.5
                }
            }
            window.setFrameOrigin(origin)
            if v.x.magnitude + v.y.magnitude < 30 {
                timer.invalidate()
            }
        }
    }

    override func scrollWheel(with event: NSEvent) {
        onVolumeScroll?(event.scrollingDeltaY)
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let menu = menuProvider?() else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    // MARK: - Placeholder

    private static let placeholder: NSImage = {
        let size = NSSize(width: 512, height: 512)
        return NSImage(size: size, flipped: false) { rect in
            NSGradient(colors: [
                NSColor(calibratedWhite: 0.14, alpha: 1),
                NSColor(calibratedWhite: 0.05, alpha: 1),
            ])?.draw(in: rect, angle: -90)

            guard let symbol = NSImage(systemSymbolName: "music.note", accessibilityDescription: "No track playing")?
                .withSymbolConfiguration(.init(pointSize: 180, weight: .thin)) else { return true }

            let tinted = NSImage(size: symbol.size, flipped: false) { symbolRect in
                symbol.draw(in: symbolRect)
                NSColor.white.withAlphaComponent(0.28).set()
                symbolRect.fill(using: .sourceAtop)
                return true
            }
            let symbolSize = tinted.size
            tinted.draw(in: NSRect(
                x: rect.midX - symbolSize.width / 2,
                y: rect.midY - symbolSize.height / 2,
                width: symbolSize.width,
                height: symbolSize.height
            ))
            return true
        }
    }()
}

final class ArtWindowController: NSWindowController, NSWindowDelegate {
    var onOpenSettings: (() -> Void)?
    var onApplyWallpaper: (() -> Void)?
    var onOpenSpotify: (() -> Void)?
    var onEnterAmbient: (() -> Void)?
    var onPlayPause: (() -> Void)?
    var onNext: (() -> Void)?
    var onPrevious: (() -> Void)?
    var onVolumeScroll: ((Double) -> Void)?

    private static let originKey = "artWindowOrigin"
    private let glowMargin: CGFloat = 70

    private let settings: AppSettings
    private let artView = ArtView()
    private var currentTrack: TrackInfo?
    private var palette = Palette.fallback
    private var glowWindow: NSWindow?

    private var lastStatus: PlaybackStatus?
    private var lastStatusDate = Date.distantPast
    private var progressTimer: Timer?

    init(settings: AppSettings) {
        self.settings = settings

        let window = ArtWindow(
            contentRect: Self.initialFrame(size: CGFloat(settings.artSize)),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = false
        window.animationBehavior = .none
        window.contentView = artView

        super.init(window: window)
        window.delegate = self

        artView.onDoubleClick = { [weak self] in self?.onOpenSpotify?() }
        artView.menuProvider = { [weak self] in self?.buildContextMenu() }
        artView.onPlayPause = { [weak self] in self?.onPlayPause?() }
        artView.onNext = { [weak self] in self?.onNext?() }
        artView.onPrevious = { [weak self] in self?.onPrevious?() }
        artView.onVolumeScroll = { [weak self] delta in self?.onVolumeScroll?(delta) }

        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.tickProgress()
        }

        applySettings()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Content updates

    func setTrack(_ track: TrackInfo?, image: NSImage?) {
        currentTrack = track
        artView.setImage(image)
        artView.toolTip = track.map { "\($0.name)\n\($0.artist) — \($0.album)" } ?? "Nothing playing"
    }

    func updatePlayback(_ status: PlaybackStatus?) {
        lastStatus = status
        lastStatusDate = Date()
        artView.setPlaying(status?.isPlaying ?? false)
        tickProgress()
    }

    func setPalette(_ newPalette: Palette) {
        palette = newPalette
        refreshGlowContents()
        // "Album colors" tints the record from the palette; setColors is a
        // no-op when the resolved colors haven't changed.
        let vinylColors = settings.vinylColorScheme.resolve(palette: palette)
        artView.setVinylColors(primary: vinylColors.primary, secondary: vinylColors.secondary)
    }

    private func tickProgress() {
        guard settings.showProgress, let status = lastStatus, status.duration > 0 else {
            artView.setProgress(0)
            return
        }
        var position = status.position
        if status.isPlaying {
            position += Date().timeIntervalSince(lastStatusDate)
        }
        artView.setProgress(CGFloat(min(max(position / status.duration, 0), 1)))
    }

    // MARK: - Settings

    func applySettings() {
        guard let window else { return }

        let size = CGFloat(settings.artSize)
        if abs(window.frame.width - size) > 0.5 {
            // Resize around the current top-left corner so the square stays put.
            let frame = NSRect(
                x: window.frame.origin.x,
                y: window.frame.maxY - size,
                width: size,
                height: size
            )
            window.setFrame(frame, display: true, animate: true)
        }

        window.level = settings.alwaysOnTop ? .floating : .normal
        window.collectionBehavior = settings.allSpaces ? [.canJoinAllSpaces, .fullScreenAuxiliary] : []
        window.ignoresMouseEvents = settings.clickThrough
        window.sharingType = settings.hideWhileSharing ? .none : .readOnly

        artView.persona = settings.persona
        artView.vinylRevolutionDuration = 60.0 / max(settings.vinylRPM, 1)
        let vinylColors = settings.vinylColorScheme.resolve(palette: palette)
        artView.setVinylColors(primary: vinylColors.primary, secondary: vinylColors.secondary)
        artView.cornerRadius = CGFloat(settings.cornerRadius)
        artView.showsProgress = settings.showProgress
        artView.hoverControlsEnabled = settings.hoverControls
        artView.physicsEnabled = settings.physicsEnabled

        updateGlow()
        window.invalidateShadow()
    }

    // MARK: - Glow

    private func updateGlow() {
        guard let window else { return }
        if settings.glowEnabled {
            let glow = ensureGlowWindow()
            glow.setFrame(window.frame.insetBy(dx: -glowMargin, dy: -glowMargin), display: true)
            glow.level = window.level
            glow.sharingType = window.sharingType
            refreshGlowContents()
        } else if let glowWindow {
            window.removeChildWindow(glowWindow)
            glowWindow.orderOut(nil)
            self.glowWindow = nil
        }
    }

    private func ensureGlowWindow() -> NSWindow {
        if let glowWindow { return glowWindow }
        let glow = NSWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        glow.isOpaque = false
        glow.backgroundColor = .clear
        glow.hasShadow = false
        glow.ignoresMouseEvents = true
        let content = NSView()
        content.wantsLayer = true
        content.layer?.contentsGravity = .resize
        glow.contentView = content
        window?.addChildWindow(glow, ordered: .below)
        glowWindow = glow
        return glow
    }

    private func refreshGlowContents() {
        guard settings.glowEnabled, let content = glowWindow?.contentView else { return }
        content.layer?.contents = Self.glowImage(color: palette.primary)
    }

    private static func glowImage(color: NSColor) -> NSImage {
        let side: CGFloat = 512
        return NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            let gradient = NSGradient(
                starting: color.withAlphaComponent(0.55),
                ending: color.withAlphaComponent(0)
            )
            gradient?.draw(in: NSBezierPath(ovalIn: rect), relativeCenterPosition: .zero)
            return true
        }
    }

    // MARK: - Window placement

    func windowDidMove(_ notification: Notification) {
        guard let window else { return }
        UserDefaults.standard.set(
            ["x": window.frame.origin.x, "y": window.frame.origin.y],
            forKey: Self.originKey
        )
    }

    private static func initialFrame(size: CGFloat) -> NSRect {
        let squareSize = NSSize(width: size, height: size)

        if let saved = UserDefaults.standard.dictionary(forKey: originKey),
           let x = saved["x"] as? Double,
           let y = saved["y"] as? Double {
            let frame = NSRect(x: x, y: y, width: squareSize.width, height: squareSize.height)
            if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(frame) }) {
                return frame
            }
        }

        guard let screen = NSScreen.main else {
            return NSRect(origin: .zero, size: squareSize)
        }
        let visible = screen.visibleFrame
        return NSRect(
            x: visible.maxX - squareSize.width - 40,
            y: visible.minY + 40,
            width: squareSize.width,
            height: squareSize.height
        )
    }

    // MARK: - Context menu

    private func buildContextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let title = currentTrack.map { "\($0.name) — \($0.artist)" } ?? "Nothing playing"
        let info = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        info.isEnabled = false
        menu.addItem(info)
        menu.addItem(.separator())

        menu.addItem(makeItem("Open Spotify", action: #selector(openSpotifyAction)))
        let wallpaperItem = makeItem("Use as Wallpaper Now", action: #selector(wallpaperNowAction))
        wallpaperItem.isEnabled = currentTrack != nil
        menu.addItem(wallpaperItem)
        menu.addItem(makeItem("Enter Ambient Mode", action: #selector(ambientAction)))
        menu.addItem(.separator())

        menu.addItem(makeItem("Settings…", action: #selector(settingsAction), key: ","))
        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: "Quit Dhun",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quit.isEnabled = true
        menu.addItem(quit)
        return menu
    }

    private func makeItem(_ title: String, action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        item.isEnabled = true
        return item
    }

    @objc private func openSpotifyAction() { onOpenSpotify?() }
    @objc private func wallpaperNowAction() { onApplyWallpaper?() }
    @objc private func settingsAction() { onOpenSettings?() }
    @objc private func ambientAction() { onEnterAmbient?() }
}
