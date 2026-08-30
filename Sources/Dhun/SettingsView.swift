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
            aboutTab
                .tabItem { Label("About", systemImage: "info.circle") }
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
                Picker("Visualization", selection: $settings.visualizerMode) {
                    ForEach(VisualizerMode.allCases, id: \.self) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                Picker("Colors", selection: $settings.visualizerColorScheme) {
                    ForEach(VisualizerColorScheme.allCases, id: \.self) { scheme in
                        Text(scheme.label).tag(scheme)
                    }
                }
                .disabled(settings.visualizerMode == .none)
                Toggle("React to sound", isOn: $settings.visualizerAudioReactive)
                    .disabled(settings.visualizerMode == .none)
                Toggle("Debug overlay (waveform, FPS, live controls)", isOn: $settings.debugOverlay)
                    .disabled(settings.visualizerMode == .none)
                Text("Full-screen generative scenes that breathe with the music — energy-cloud plasma, ink blooms that remember the song, a 14,000-bird murmuration, bass-triggered volumetric explosions, a moonlit flight, drifting cloudscapes, a calm isoline flow, and spectrum-painted movement. Driven by Spotify's actual audio — macOS asks once for the screen & system audio recording permission; Dhun never touches the microphone. With React to sound off, scenes keep their idle drift and no audio is captured.")
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

    // MARK: - About

    private var appVersion: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        return "Version \(short)"
    }

    private var aboutTab: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Dhun · धुन")
                            .font(.title2.weight(.bold))
                        Text(appVersion)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Text("Whatever Spotify is playing, living on your desktop as art.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 6)
            }

            Section("Links") {
                Link(destination: URL(string: "https://github.com/Ayush-pbh/dhun")!) {
                    Label("Source on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                }
                Link(destination: URL(string: "https://github.com/Ayush-pbh/dhun/issues")!) {
                    Label("Report an issue", systemImage: "ladybug")
                }
                Link(destination: URL(string: "https://ayusht.me")!) {
                    Label("ayusht.me", systemImage: "globe")
                }
            }

            Section("Credits") {
                LabeledContent("App & design", value: "Ayush Tripathi")
                LabeledContent("Ambience Plasma", value: "Ayush Tripathi")
                LabeledContent("Ink in Water · Murmuration · Movement", value: "Ayush Tripathi")
                LabeledContent("Volumetric Explosion", value: "Duke")
                LabeledContent("MoonWalk", value: "Nikos Papadopoulos (4rknova)")
                LabeledContent("Cloud Canal", value: "Stéphane Cuillerdier (Aiekick)")
                LabeledContent("Calm Flow", value: "Sebastien Durand")
                Text("The last four scenes are adapted from Shadertoy works published under CC BY-NC-SA 3.0; each carries a full attribution header in the source and the README.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("License") {
                Link(destination: URL(string: "https://github.com/Ayush-pbh/dhun/blob/main/LICENSE")!) {
                    Label("CC BY-NC-SA 4.0", systemImage: "doc.text")
                }
                Text("© 2026 Ayush Tripathi. Free to use, modify, and share for non-commercial purposes, with attribution, under the same license.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Roadmap") {
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
