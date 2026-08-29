import AppKit
import SwiftUI

/// Full-screen "now playing" scene: the artwork drifting slowly as a blurred
/// backdrop with the sharp cover and big typography centered, plus an
/// optional audio-reactive visualizer. Click anywhere or press Esc to leave.
final class AmbientController {
    private let model: NowPlayingModel
    private let settings: AppSettings
    private let visualizer = AudioVisualizerEngine()
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
            onExit: { [weak self] in self?.exit() }
        ))
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = w

        if settings.visualizerEnabled {
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

    /// Applies a visualizer toggle change while ambient mode is open.
    func refreshVisualizer() {
        guard isActive else { return }
        if settings.visualizerEnabled {
            visualizer.start()
        } else {
            visualizer.stop()
        }
    }

    private static func showCapturePermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "The visualizer needs audio access"
        alert.informativeText = """
        Dhun draws the ambient visualizer from Spotify's actual audio, which macOS \
        exposes through the screen & system audio recording permission.

        Open System Settings → Privacy & Security → Screen & System Audio Recording, \
        enable Dhun, then relaunch Dhun.
        """
        alert.runModal()
    }
}

private final class KeyableBorderlessWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

struct AmbientView: View {
    @ObservedObject var model: NowPlayingModel
    @ObservedObject var settings: AppSettings
    @ObservedObject var visualizer: AudioVisualizerEngine
    var onExit: () -> Void
    @State private var drift = false

    var body: some View {
        ZStack {
            Color.black

            if let artwork = model.artwork {
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

            if settings.visualizerEnabled {
                visualization
                    .allowsHitTesting(false)
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
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture { onExit() }
        .preferredColorScheme(.dark)
    }

    private var visualization: some View {
        Canvas { context, size in
            let primary = Color(nsColor: model.palette.primary)
            let secondary = Color(nsColor: model.palette.secondary)
            switch settings.visualizerStyle {
            case .bars:
                drawBars(context: &context, size: size, primary: primary, secondary: secondary)
            case .wave:
                drawWave(context: &context, size: size, primary: primary)
            }
        }
    }

    private func drawBars(context: inout GraphicsContext, size: CGSize, primary: Color, secondary: Color) {
        let bands = visualizer.bands
        guard !bands.isEmpty else { return }
        let spacing: CGFloat = 5
        let barWidth = (size.width - spacing * CGFloat(bands.count + 1)) / CGFloat(bands.count)
        guard barWidth > 0 else { return }
        let maxHeight = size.height * 0.30

        context.addFilter(.shadow(color: primary.opacity(0.7), radius: 14))
        let gradient = Gradient(colors: [secondary.opacity(0.9), primary, .white.opacity(0.95)])
        for (index, level) in bands.enumerated() {
            let height = max(4, CGFloat(level) * maxHeight)
            let x = spacing + CGFloat(index) * (barWidth + spacing)
            let rect = CGRect(x: x, y: size.height - height, width: barWidth, height: height)
            let path = Path(roundedRect: rect, cornerRadius: barWidth * 0.3)
            context.fill(path, with: .linearGradient(
                gradient,
                startPoint: CGPoint(x: rect.midX, y: size.height),
                endPoint: CGPoint(x: rect.midX, y: size.height - maxHeight)
            ))
        }
    }

    private func drawWave(context: inout GraphicsContext, size: CGSize, primary: Color) {
        let samples = visualizer.waveform
        guard samples.count > 1 else { return }
        let baseline = size.height * 0.80
        let amplitude = size.height * 0.13

        var path = Path()
        for (index, value) in samples.enumerated() {
            let x = size.width * CGFloat(index) / CGFloat(samples.count - 1)
            let y = baseline - CGFloat(value) * amplitude
            if index == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        context.addFilter(.shadow(color: primary.opacity(0.8), radius: 10))
        context.stroke(path, with: .color(primary), style: StrokeStyle(lineWidth: 2.5, lineJoin: .round))
    }
}
