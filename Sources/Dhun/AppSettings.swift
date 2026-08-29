import Foundation
import Combine

enum WallpaperStyle: String, CaseIterable, Hashable {
    case blurredBackdrop
    case fillScreen
    case paletteGradient

    var label: String {
        switch self {
        case .blurredBackdrop: return "Centered on blurred art"
        case .fillScreen: return "Art fills the screen"
        case .paletteGradient: return "Palette gradient"
        }
    }
}

enum ArtPersona: String, CaseIterable, Hashable {
    case plainSquare
    case vinyl

    var label: String {
        switch self {
        case .plainSquare: return "Plain square"
        case .vinyl: return "Vinyl record"
        }
    }
}

final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private static let defaults = UserDefaults.standard

    // MARK: Square

    @Published var persona: ArtPersona {
        didSet { Self.defaults.set(persona.rawValue, forKey: "persona") }
    }
    @Published var artSize: Double {
        didSet { Self.defaults.set(artSize, forKey: "artSize") }
    }
    @Published var vinylRPM: Double {
        didSet { Self.defaults.set(vinylRPM, forKey: "vinylRPM") }
    }
    @Published var vinylColorScheme: VinylColorScheme {
        didSet { Self.defaults.set(vinylColorScheme.rawValue, forKey: "vinylColorScheme") }
    }
    @Published var cornerRadius: Double {
        didSet { Self.defaults.set(cornerRadius, forKey: "cornerRadius") }
    }
    @Published var alwaysOnTop: Bool {
        didSet { Self.defaults.set(alwaysOnTop, forKey: "alwaysOnTop") }
    }
    @Published var allSpaces: Bool {
        didSet { Self.defaults.set(allSpaces, forKey: "allSpaces") }
    }
    @Published var clickThrough: Bool {
        didSet { Self.defaults.set(clickThrough, forKey: "clickThrough") }
    }
    @Published var physicsEnabled: Bool {
        didSet { Self.defaults.set(physicsEnabled, forKey: "physicsEnabled") }
    }
    @Published var showProgress: Bool {
        didSet { Self.defaults.set(showProgress, forKey: "showProgress") }
    }
    @Published var hoverControls: Bool {
        didSet { Self.defaults.set(hoverControls, forKey: "hoverControls") }
    }
    @Published var glowEnabled: Bool {
        didSet { Self.defaults.set(glowEnabled, forKey: "glowEnabled") }
    }

    // MARK: Wallpaper & desktop

    @Published var wallpaperEnabled: Bool {
        didSet { Self.defaults.set(wallpaperEnabled, forKey: "wallpaperEnabled") }
    }
    @Published var wallpaperStyle: WallpaperStyle {
        didSet { Self.defaults.set(wallpaperStyle.rawValue, forKey: "wallpaperStyle") }
    }
    @Published var desktopVinylEnabled: Bool {
        didSet { Self.defaults.set(desktopVinylEnabled, forKey: "desktopVinylEnabled") }
    }

    // MARK: Extras

    @Published var notchIslandEnabled: Bool {
        didSet { Self.defaults.set(notchIslandEnabled, forKey: "notchIslandEnabled") }
    }
    @Published var toastEnabled: Bool {
        didSet { Self.defaults.set(toastEnabled, forKey: "toastEnabled") }
    }
    @Published var visualizerMode: VisualizerMode {
        didSet { Self.defaults.set(visualizerMode.rawValue, forKey: "visualizerMode") }
    }
    @Published var visualizerColorScheme: VisualizerColorScheme {
        didSet { Self.defaults.set(visualizerColorScheme.rawValue, forKey: "plasmaColorScheme") }
    }
    @Published var debugOverlay: Bool {
        didSet { Self.defaults.set(debugOverlay, forKey: "debugOverlay") }
    }

    // MARK: General

    @Published var hideDockIcon: Bool {
        didSet { Self.defaults.set(hideDockIcon, forKey: "hideDockIcon") }
    }
    @Published var statusItemEnabled: Bool {
        didSet { Self.defaults.set(statusItemEnabled, forKey: "statusItemEnabled") }
    }
    @Published var hideWhileSharing: Bool {
        didSet { Self.defaults.set(hideWhileSharing, forKey: "hideWhileSharing") }
    }
    @Published var launchAtLogin: Bool {
        didSet { Self.defaults.set(launchAtLogin, forKey: "launchAtLogin") }
    }

    private init() {
        let d = Self.defaults
        persona = ArtPersona(rawValue: d.string(forKey: "persona") ?? "") ?? .plainSquare
        artSize = d.object(forKey: "artSize") as? Double ?? 240
        vinylRPM = d.object(forKey: "vinylRPM") as? Double ?? 33
        vinylColorScheme = VinylColorScheme(rawValue: d.string(forKey: "vinylColorScheme") ?? "") ?? .classic
        cornerRadius = d.object(forKey: "cornerRadius") as? Double ?? 0
        alwaysOnTop = d.object(forKey: "alwaysOnTop") as? Bool ?? true
        allSpaces = d.object(forKey: "allSpaces") as? Bool ?? true
        clickThrough = d.object(forKey: "clickThrough") as? Bool ?? false
        physicsEnabled = d.object(forKey: "physicsEnabled") as? Bool ?? false
        showProgress = d.object(forKey: "showProgress") as? Bool ?? false
        hoverControls = d.object(forKey: "hoverControls") as? Bool ?? false
        glowEnabled = d.object(forKey: "glowEnabled") as? Bool ?? false
        wallpaperEnabled = d.object(forKey: "wallpaperEnabled") as? Bool ?? false
        wallpaperStyle = WallpaperStyle(rawValue: d.string(forKey: "wallpaperStyle") ?? "") ?? .blurredBackdrop
        desktopVinylEnabled = d.object(forKey: "desktopVinylEnabled") as? Bool ?? false
        notchIslandEnabled = d.object(forKey: "notchIslandEnabled") as? Bool ?? false
        toastEnabled = d.object(forKey: "toastEnabled") as? Bool ?? false
        if let raw = d.string(forKey: "visualizerMode"), let mode = VisualizerMode(rawValue: raw) {
            visualizerMode = mode
        } else {
            // Migrate from the old boolean toggle.
            visualizerMode = (d.object(forKey: "visualizerEnabled") as? Bool ?? false) ? .plasma : .none
        }
        visualizerColorScheme = VisualizerColorScheme(rawValue: d.string(forKey: "plasmaColorScheme") ?? "") ?? .electricBlue
        debugOverlay = d.object(forKey: "debugOverlay") as? Bool ?? false
        hideDockIcon = d.object(forKey: "hideDockIcon") as? Bool ?? false
        statusItemEnabled = d.object(forKey: "statusItemEnabled") as? Bool ?? true
        hideWhileSharing = d.object(forKey: "hideWhileSharing") as? Bool ?? false
        launchAtLogin = d.object(forKey: "launchAtLogin") as? Bool ?? false
    }
}
