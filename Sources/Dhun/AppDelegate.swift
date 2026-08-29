import AppKit
import Combine
import ServiceManagement
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings.shared
    private let spotify = SpotifyController()
    private let wallpaperManager = WallpaperManager()
    private let model = NowPlayingModel()
    private let toastController = ToastController()
    private let desktopSceneController = DesktopSceneController()

    private var artController: ArtWindowController!
    private var statusItemController: StatusItemController!
    private var notchController: NotchIslandController!
    private var ambientController: AmbientController!

    private var settingsWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()

    private var currentTrack: TrackInfo?
    private var currentArt: NSImage?
    private var currentArtURL: URL?
    private var lastWallpaperURL: URL?
    private var lastPaletteURL: URL?
    private var lastToastKey: String?
    private var volumeTarget: Double?
    private var volumeSendTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(settings.hideDockIcon ? .accessory : .regular)
        buildMenu()

        ambientController = AmbientController(model: model, settings: settings)

        artController = ArtWindowController(settings: settings)
        artController.onOpenSettings = { [weak self] in self?.openSettings() }
        artController.onApplyWallpaper = { [weak self] in self?.applyWallpaperNow(interactive: true) }
        artController.onOpenSpotify = { Self.openSpotify() }
        artController.onEnterAmbient = { [weak self] in self?.ambientController.toggle() }
        artController.onPlayPause = { [weak self] in self?.spotify.playPause() }
        artController.onNext = { [weak self] in self?.spotify.nextTrack() }
        artController.onPrevious = { [weak self] in self?.spotify.previousTrack() }
        artController.onVolumeScroll = { [weak self] delta in self?.handleVolumeScroll(delta) }
        artController.showWindow(nil)
        artController.window?.makeKeyAndOrderFront(nil)

        statusItemController = StatusItemController(settings: settings)
        statusItemController.onPlayPause = { [weak self] in self?.spotify.playPause() }
        statusItemController.onNext = { [weak self] in self?.spotify.nextTrack() }
        statusItemController.onPrevious = { [weak self] in self?.spotify.previousTrack() }
        statusItemController.onOpenSettings = { [weak self] in self?.openSettings() }
        statusItemController.onEnterAmbient = { [weak self] in self?.ambientController.toggle() }
        statusItemController.onApplyWallpaper = { [weak self] in self?.applyWallpaperNow(interactive: true) }
        statusItemController.onToggleClickThrough = { [weak self] in self?.settings.clickThrough.toggle() }
        statusItemController.setEnabled(settings.statusItemEnabled)

        let commands = PlayerCommands(
            playPause: { [weak self] in self?.spotify.playPause() },
            next: { [weak self] in self?.spotify.nextTrack() },
            previous: { [weak self] in self?.spotify.previousTrack() }
        )
        notchController = NotchIslandController(model: model, commands: commands)
        notchController.setEnabled(settings.notchIslandEnabled)

        desktopSceneController.setEnabled(settings.desktopVinylEnabled)
        desktopSceneController.setRevolutionDuration(60.0 / max(settings.vinylRPM, 1))
        applyDesktopVinylColors()

        spotify.onUpdate = { [weak self] track, image, imageURL in
            self?.handleTrackUpdate(track: track, image: image, imageURL: imageURL)
        }
        spotify.onStatus = { [weak self] status in self?.handleStatusUpdate(status) }
        spotify.onPermissionProblem = { [weak self] in self?.showPermissionAlert() }
        spotify.start()

        settings.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                // objectWillChange fires before the value lands; apply on the next tick.
                DispatchQueue.main.async { self?.settingsChanged() }
            }
            .store(in: &cancellables)

        applyLaunchAtLogin()
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    // MARK: - Updates from Spotify

    private func handleTrackUpdate(track: TrackInfo?, image: NSImage?, imageURL: URL?) {
        currentTrack = track
        currentArt = image
        currentArtURL = imageURL
        model.track = track
        model.artwork = image

        artController.setTrack(track, image: image)
        statusItemController.update(track: track, artwork: image, isPlaying: track?.isPlaying ?? false)
        desktopSceneController.update(artwork: image, palette: model.palette, isPlaying: track?.isPlaying ?? false)

        maybeShowToast(for: track)
        processArtworkChange(image: image, imageURL: imageURL)
    }

    private func handleStatusUpdate(_ status: PlaybackStatus?) {
        model.status = status
        model.statusDate = Date()
        artController.updatePlayback(status)
        desktopSceneController.setSpinning(status?.isPlaying ?? false)
    }

    private func maybeShowToast(for track: TrackInfo?) {
        guard let track else { return }
        let key = "\(track.name)|\(track.artist)|\(track.album)"
        guard key != lastToastKey else { return }
        let isFirst = lastToastKey == nil
        lastToastKey = key
        guard settings.toastEnabled, !isFirst else { return }
        // Give the new artwork a beat to download so the toast shows the
        // right cover instead of the previous track's.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, self.lastToastKey == key else { return }
            self.toastController.show(track: track, artwork: self.currentArt)
        }
    }

    private func processArtworkChange(image: NSImage?, imageURL: URL?) {
        guard let image, let imageURL else { return }
        if imageURL == lastPaletteURL {
            autoApplyWallpaperIfNeeded()
            return
        }
        lastPaletteURL = imageURL
        guard let copy = image.copy() as? NSImage else { return }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let palette = PaletteExtractor.extract(from: copy)
            DispatchQueue.main.async {
                guard let self, self.lastPaletteURL == imageURL else { return }
                self.model.palette = palette
                self.artController.setPalette(palette)
                self.applyDesktopVinylColors()
                self.desktopSceneController.update(
                    artwork: self.currentArt,
                    palette: palette,
                    isPlaying: self.currentTrack?.isPlaying ?? false
                )
                self.autoApplyWallpaperIfNeeded()
            }
        }
    }

    private func autoApplyWallpaperIfNeeded() {
        guard settings.wallpaperEnabled,
              let art = currentArt,
              let url = currentArtURL,
              url != lastWallpaperURL else { return }
        lastWallpaperURL = url
        wallpaperManager.apply(art: art, style: settings.wallpaperStyle, palette: model.palette) { error in
            if let error {
                NSLog("Wallpaper update failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Settings changes

    private func settingsChanged() {
        // Click-through would otherwise lock the user out of the square;
        // make sure the menu bar escape hatch stays available.
        if settings.clickThrough, !settings.statusItemEnabled {
            settings.statusItemEnabled = true
            return // this triggers another settingsChanged pass
        }

        artController.applySettings()

        let policy: NSApplication.ActivationPolicy = settings.hideDockIcon ? .accessory : .regular
        if NSApp.activationPolicy() != policy {
            NSApp.setActivationPolicy(policy)
            NSApp.activate(ignoringOtherApps: true)
            artController.window?.orderFrontRegardless()
            settingsWindow?.orderFrontRegardless()
        }

        statusItemController.setEnabled(settings.statusItemEnabled)
        notchController.setEnabled(settings.notchIslandEnabled)
        desktopSceneController.setEnabled(settings.desktopVinylEnabled)
        desktopSceneController.setRevolutionDuration(60.0 / max(settings.vinylRPM, 1))
        applyDesktopVinylColors()
        if settings.desktopVinylEnabled {
            desktopSceneController.update(
                artwork: currentArt,
                palette: model.palette,
                isPlaying: currentTrack?.isPlaying ?? false
            )
        }
        ambientController.refreshVisualizer()
        applyLaunchAtLogin()
        autoApplyWallpaperIfNeeded()
    }

    private func applyDesktopVinylColors() {
        let colors = settings.vinylColorScheme.resolve(palette: model.palette)
        desktopSceneController.setVinylColors(primary: colors.primary, secondary: colors.secondary)
    }

    private func applyLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if settings.launchAtLogin, service.status != .enabled {
                try service.register()
            } else if !settings.launchAtLogin, service.status == .enabled {
                try service.unregister()
            }
        } catch {
            NSLog("Launch-at-login change failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Actions

    @objc func openSettings() {
        if settingsWindow == nil {
            let hosting = NSHostingController(rootView: SettingsView(
                settings: settings,
                onApplyWallpaperNow: { [weak self] in self?.applyWallpaperNow(interactive: true) },
                onEnterAmbient: { [weak self] in self?.ambientController.enter() }
            ))
            let window = NSWindow(contentViewController: hosting)
            window.title = "Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc func toggleAmbient() {
        ambientController.toggle()
    }

    private func applyWallpaperNow(interactive: Bool) {
        guard let art = currentArt else {
            if interactive {
                let alert = NSAlert()
                alert.messageText = "Nothing to apply"
                alert.informativeText = "Play something in Spotify first — the album art will then be available as a wallpaper."
                alert.runModal()
            }
            return
        }
        lastWallpaperURL = currentArtURL
        wallpaperManager.apply(art: art, style: settings.wallpaperStyle, palette: model.palette) { error in
            guard let error else { return }
            if interactive {
                NSAlert(error: error).runModal()
            } else {
                NSLog("Wallpaper update failed: \(error.localizedDescription)")
            }
        }
    }

    private func handleVolumeScroll(_ delta: Double) {
        guard settings.hoverControls else { return }
        let base = volumeTarget ?? Double(model.status?.volume ?? 60)
        volumeTarget = min(100, max(0, base + delta))
        guard volumeSendTimer == nil else { return }
        volumeSendTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.volumeSendTimer = nil
            if let target = self.volumeTarget {
                self.volumeTarget = nil
                self.spotify.setVolume(Int(target.rounded()))
            }
        }
    }

    private static func openSpotify() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.spotify.client") else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    private func showPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "Automation permission needed"
        alert.informativeText = """
        Dhun reads the current track from the Spotify app using Apple events, \
        and macOS has blocked that.

        Open System Settings → Privacy & Security → Automation, find Dhun, \
        and allow it to control Spotify. Then relaunch the app.
        """
        alert.runModal()
    }

    // MARK: - Menu

    private func buildMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)

        let appMenu = NSMenu()
        appMenu.addItem(
            withTitle: "About Dhun",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        appMenu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        appMenu.addItem(settingsItem)

        let ambientItem = NSMenuItem(title: "Enter Ambient Mode", action: #selector(toggleAmbient), keyEquivalent: "")
        ambientItem.target = self
        appMenu.addItem(ambientItem)
        appMenu.addItem(.separator())

        appMenu.addItem(
            withTitle: "Hide Dhun",
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h"
        )
        appMenu.addItem(
            withTitle: "Quit Dhun",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )

        appMenuItem.submenu = appMenu
        NSApp.mainMenu = mainMenu
    }
}
