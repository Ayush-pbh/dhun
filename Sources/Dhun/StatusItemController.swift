import AppKit

/// The menu bar presence: a tiny rounded artwork thumbnail (or a music note
/// when idle) with a now-playing menu and quick controls.
final class StatusItemController: NSObject, NSMenuDelegate {
    var onPlayPause: (() -> Void)?
    var onNext: (() -> Void)?
    var onPrevious: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onEnterAmbient: (() -> Void)?
    var onApplyWallpaper: (() -> Void)?
    var onToggleClickThrough: (() -> Void)?

    private let settings: AppSettings
    private var statusItem: NSStatusItem?
    private var track: TrackInfo?
    private var isPlaying = false

    init(settings: AppSettings) {
        self.settings = settings
    }

    func setEnabled(_ enabled: Bool) {
        if enabled {
            guard statusItem == nil else { return }
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            let menu = NSMenu()
            menu.delegate = self
            item.menu = menu
            statusItem = item
            refreshButton(artwork: nil)
        } else if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
    }

    func update(track: TrackInfo?, artwork: NSImage?, isPlaying: Bool) {
        self.track = track
        self.isPlaying = isPlaying
        refreshButton(artwork: artwork)
    }

    private func refreshButton(artwork: NSImage?) {
        statusItem?.button?.image = Self.menuBarImage(from: artwork)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.autoenablesItems = false

        let title = track.map { "\($0.name) — \($0.artist)" } ?? "Nothing playing"
        let info = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        info.isEnabled = false
        menu.addItem(info)
        menu.addItem(.separator())

        menu.addItem(makeItem(isPlaying ? "Pause" : "Play", action: #selector(playPauseAction)))
        menu.addItem(makeItem("Next Track", action: #selector(nextAction)))
        menu.addItem(makeItem("Previous Track", action: #selector(previousAction)))
        menu.addItem(.separator())

        menu.addItem(makeItem("Enter Ambient Mode", action: #selector(ambientAction)))
        let wallpaper = makeItem("Use as Wallpaper Now", action: #selector(wallpaperAction))
        wallpaper.isEnabled = track != nil
        menu.addItem(wallpaper)
        menu.addItem(.separator())

        let clickThrough = makeItem("Click-Through Square", action: #selector(clickThroughAction))
        clickThrough.state = settings.clickThrough ? .on : .off
        menu.addItem(clickThrough)
        menu.addItem(makeItem("Settings…", action: #selector(settingsAction)))
        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: "Quit Dhun",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: ""
        )
        quit.target = NSApp
        quit.isEnabled = true
        menu.addItem(quit)
    }

    private func makeItem(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.isEnabled = true
        return item
    }

    @objc private func playPauseAction() { onPlayPause?() }
    @objc private func nextAction() { onNext?() }
    @objc private func previousAction() { onPrevious?() }
    @objc private func ambientAction() { onEnterAmbient?() }
    @objc private func wallpaperAction() { onApplyWallpaper?() }
    @objc private func settingsAction() { onOpenSettings?() }
    @objc private func clickThroughAction() { onToggleClickThrough?() }

    private static func menuBarImage(from artwork: NSImage?) -> NSImage {
        guard let artwork else {
            let symbol = NSImage(systemSymbolName: "music.note", accessibilityDescription: "Dhun")?
                .withSymbolConfiguration(.init(pointSize: 14, weight: .medium)) ?? NSImage()
            symbol.isTemplate = true
            return symbol
        }
        let side: CGFloat = 18
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).addClip()
            artwork.draw(in: rect)
            return true
        }
        image.isTemplate = false
        return image
    }
}
