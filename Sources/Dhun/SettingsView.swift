import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    var onApplyWallpaperNow: () -> Void
    var onEnterAmbient: () -> Void

    var body: some View {
        TabView {
            squareTab
                .tabItem { Label("Square", systemImage: "square.on.square") }
            wallpaperTab
                .tabItem { Label("Wallpaper", systemImage: "photo") }
            extrasTab
                .tabItem { Label("Extras", systemImage: "sparkles") }
            generalTab
                .tabItem { Label("General", systemImage: "gearshape") }
            labsTab
                .tabItem { Label("Labs", systemImage: "testtube.2") }
        }
        .frame(width: 500, height: 580)
    }

    // MARK: - Square

    private var squareTab: some View {
        Form {
            Section("Appearance") {
                Picker("Persona", selection: $settings.persona) {
                    ForEach(ArtPersona.allCases, id: \.self) { persona in
                        Text(persona.label).tag(persona)
                    }
                }
                .pickerStyle(.segmented)
                Slider(value: $settings.artSize, in: 150...600, step: 10) {
                    Text("Size: \(Int(settings.artSize)) pt")
                }
                Slider(value: $settings.vinylRPM, in: 5...78, step: 1) {
                    Text("Spin speed: \(Int(settings.vinylRPM)) RPM")
                }
                .disabled(settings.persona != .vinyl)
                Picker("Vinyl colors", selection: $settings.vinylColorScheme) {
                    ForEach(VinylColorScheme.allCases, id: \.self) { scheme in
                        Text(scheme.label).tag(scheme)
                    }
                }
                if settings.vinylColorScheme == .album {
                    Text("The record's grooves and sheen are tinted from the current album cover. Also applies to the desktop vinyl scene.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Slider(value: $settings.cornerRadius, in: 0...40, step: 1) {
                    Text("Corner radius: \(Int(settings.cornerRadius)) pt")
                }
                .disabled(settings.persona == .vinyl)
            }

            Section("Behavior") {
                Toggle("Keep above other windows", isOn: $settings.alwaysOnTop)
                Toggle("Show on all Spaces", isOn: $settings.allSpaces)
                Toggle("Momentum when thrown", isOn: $settings.physicsEnabled)
                Toggle("Click-through (decoration only)", isOn: $settings.clickThrough)
                if settings.clickThrough {
                    Text("The square ignores all clicks. Turn this back off here or from the menu bar icon.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Overlays") {
                Toggle("Progress indicator", isOn: $settings.showProgress)
                Toggle("Playback controls on hover (scroll for volume)", isOn: $settings.hoverControls)
                Toggle("Ambient glow behind the art", isOn: $settings.glowEnabled)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Wallpaper

    private var wallpaperTab: some View {
        Form {
            Section("Wallpaper") {
                Toggle("Set album art as wallpaper automatically", isOn: $settings.wallpaperEnabled)
                Picker("Style", selection: $settings.wallpaperStyle) {
                    ForEach(WallpaperStyle.allCases, id: \.self) { style in
                        Text(style.label).tag(style)
                    }
                }
                Button("Apply Now") {
                    onApplyWallpaperNow()
                }
            }

            Section("Live Desktop") {
                Toggle("Vinyl scene behind desktop icons", isOn: $settings.desktopVinylEnabled)
                Text("A live record rendered just above your wallpaper — it actually spins while music plays and freezes on pause.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Extras

    private var extrasTab: some View {
        Form {
            Section("Notch Island") {
                Toggle("Show island near the camera", isOn: $settings.notchIslandEnabled)
                Text("Move the pointer to the top-center of the screen and the island expands with playback controls. Works best on Macs with a notch.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Moments") {
                Toggle("Track-change toast", isOn: $settings.toastEnabled)
                Button("Enter Ambient Mode") {
                    onEnterAmbient()
                }
                Text("Full-screen now-playing scene. Click anywhere or press Esc to leave.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Ambient Visualizer") {
                Toggle("Audio-reactive visualizer", isOn: $settings.visualizerEnabled)
                Picker("Style", selection: $settings.visualizerStyle) {
                    ForEach(VisualizerStyle.allCases, id: \.self) { style in
                        Text(style.label).tag(style)
                    }
                }
                Text("Draws from Spotify's actual audio, tinted with the album palette. macOS asks once for the screen & system audio recording permission — Dhun listens only to Spotify's output, never the microphone.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - General

    private var generalTab: some View {
        Form {
            Section("App") {
                Toggle("Hide Dock icon", isOn: $settings.hideDockIcon)
                if settings.hideDockIcon {
                    Text("Settings stays available from the menu bar icon and the album art’s right-click menu.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Toggle("Show menu bar icon", isOn: $settings.statusItemEnabled)
                    .disabled(settings.clickThrough)
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
            }

            Section("Privacy") {
                Toggle("Invisible to screen sharing & recordings", isOn: $settings.hideWhileSharing)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Labs

    private var labsTab: some View {
        Form {
            Section("Planned — not built yet") {
                Label("Album wall — listening-history collage wallpaper", systemImage: "square.grid.3x3")
                    .foregroundStyle(.secondary)
                Label("Cassette & CD personas", systemImage: "recordingtape")
                    .foregroundStyle(.secondary)
                Label("Shortcuts / App Intents automation", systemImage: "bolt")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
