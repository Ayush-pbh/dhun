import AppKit
import SwiftUI

/// Full-screen "now playing" scene: the artwork drifting slowly as a blurred
/// backdrop with the sharp cover and big typography centered, plus an
/// optional audio-reactive visualizer. Click anywhere or press Esc to leave.
final class AmbientController {
    private let model: NowPlayingModel
    private let settings: AppSettings
    private let visualizer = AudioVisualizerEngine()
    private let stats = VisualizerStats()
    private var window: NSWindow?
    private var keyMonitor: Any?

    init(model: NowPlayingModel, settings: AppSettings) {
        self.model = model
        self.settings = settings
        visualizer.onCaptureProblem = { Self.showCapturePermissionAlert() }
    }

    var isActive: Bool { window != nil }

    func toggle() {
        if isActive {
            exit()
        } else {
            enter()
        }
    }

    func enter() {
        guard window == nil, let screen = NSScreen.main else { return }

        let w = KeyableBorderlessWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        w.isOpaque = true
        w.backgroundColor = .black
        w.level = .modalPanel
        w.collectionBehavior = [.fullScreenAuxiliary]
        w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(rootView: AmbientView(
            model: model,
            settings: settings,
            visualizer: visualizer,
            stats: stats,
            onExit: { [weak self] in self?.exit() }
        ))
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = w

        if settings.visualizerMode != .none {
            visualizer.start()
        }

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Esc
                self?.exit()
                return nil
            }
            return event
        }
    }

    func exit() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        visualizer.stop()
        window?.orderOut(nil)
        window = nil
    }

    /// Applies a visualizer mode change while ambient mode is open.
    func refreshVisualizer() {
        guard isActive else { return }
        if settings.visualizerMode != .none {
            visualizer.start()
        } else {
            visualizer.stop()
        }
    }

    static func showCapturePermissionAlert() {
        let alert = NSAlert()
        // The fullscreen ambient window sits at modal-panel level; make sure
        // this alert lands above it, not behind it.
        alert.window.level = .screenSaver
        alert.messageText = "The visualizer needs audio access"
        alert.informativeText = """
        Dhun draws the visualizers from Spotify's actual audio, which macOS \
        exposes through the screen & system audio recording permission — and \
        that permission is currently off for Dhun. macOS only asks once, so \
        it has to be enabled manually:

        System Settings → Privacy & Security → Screen & System Audio \
        Recording → enable Dhun, then quit and reopen Dhun.
        """
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}

private final class KeyableBorderlessWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

struct AmbientView: View {
    @ObservedObject var model: NowPlayingModel
    @ObservedObject var settings: AppSettings
    let visualizer: AudioVisualizerEngine
    let stats: VisualizerStats
    var onExit: () -> Void
    @State private var drift = false

    var body: some View {
        ZStack {
            Color.black

            if settings.visualizerMode != .none {
                // The visualizer replaces the blurred-cover backdrop; the
                // Metal view drives its own 60 fps loop, no SwiftUI churn.
                let tints = settings.visualizerColorScheme.resolve(palette: model.palette)
                MetalVisualization(
                    engine: visualizer,
                    mode: settings.visualizerMode,
                    colorA: tints.body,
                    colorB: tints.accent,
                    stats: stats
                )
                .allowsHitTesting(false)
            } else if let artwork = model.artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .scaleEffect(drift ? 1.12 : 1.0)
                    .blur(radius: 90)
                    .opacity(0.75)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 25).repeatForever(autoreverses: true)) {
                            drift = true
                        }
                    }
            }

            VStack(spacing: 30) {
                Group {
                    if let artwork = model.artwork {
                        Image(nsImage: artwork)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        ZStack {
                            Color(white: 0.1)
                            Image(systemName: "music.note")
                                .font(.system(size: 80, weight: .thin))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(width: 320, height: 320)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(color: .black.opacity(0.6), radius: 45, y: 18)

                VStack(spacing: 8) {
                    Text(model.track?.name ?? "Nothing playing")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                    if let track = model.track {
                        Text("\(track.artist) — \(track.album)")
                            .font(.system(size: 17))
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 60)
            }
        }
        .overlay(alignment: .topTrailing) {
            if settings.debugOverlay {
                DebugOverlay(engine: visualizer, stats: stats)
                    .padding(.top, 44)
                    .padding(.trailing, 28)
            }
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture { onExit() }
        .preferredColorScheme(.dark)
    }

}

/// Debug readout: live raw waveform straight from the capture pipeline and
/// the Metal view's measured frame rate. Isolated in its own view so its
/// high-frequency updates don't re-render the rest of the ambient scene.
private struct DebugOverlay: View {
    @ObservedObject var engine: AudioVisualizerEngine
    @ObservedObject var stats: VisualizerStats

    var body: some View {
        VStack(alignment: .trailing, spacing: 5) {
            Canvas { context, size in
                let samples = engine.waveform
                guard samples.count > 1 else { return }
                let midY = size.height / 2
                var path = Path()
                for (index, value) in samples.enumerated() {
                    let x = size.width * CGFloat(index) / CGFloat(samples.count - 1)
                    let y = midY - CGFloat(value) * midY * 0.9
                    if index == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
                context.stroke(path, with: .color(.green), lineWidth: 1)
            }
            .frame(width: 190, height: 46)
            .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.white.opacity(0.15)))

            Text(String(
                format: "%.0f fps · lvl %.2f · bass %.2f",
                stats.fps,
                engine.signals.level,
                engine.signals.bass
            ))
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(.green.opacity(0.9))
        }
    }
}
