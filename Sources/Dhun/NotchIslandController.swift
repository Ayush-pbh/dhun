import AppKit
import SwiftUI

/// A little island that lives at the top-center of the screen (hugging the
/// notch on Macs that have one). Invisible until the pointer approaches the
/// camera area, then it expands into a now-playing panel with controls.
final class NotchIslandController {
    private let model: NowPlayingModel
    private let commands: PlayerCommands
    private var window: NSWindow?
    private var pollTimer: Timer?
    private var expanded = false

    init(model: NowPlayingModel, commands: PlayerCommands) {
        self.model = model
        self.commands = commands
    }

    func setEnabled(_ enabled: Bool) {
        if enabled {
            start()
        } else {
            stop()
        }
    }

    private static var targetScreen: NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main
    }

    private func start() {
        guard window == nil, let screen = Self.targetScreen else { return }

        let size = NSSize(width: 360, height: 88)
        let frame = NSRect(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.maxY - size.height,
            width: size.width,
            height: size.height
        )
        let w = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = false
        w.level = .statusBar
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        w.ignoresMouseEvents = true
        w.alphaValue = 0
        w.contentView = NSHostingView(rootView: NotchIslandView(model: model, commands: commands))
        w.orderFrontRegardless()
        window = w

        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        window?.orderOut(nil)
        window = nil
        expanded = false
    }

    private func tick() {
        guard let window, let screen = Self.targetScreen else { return }
        let mouse = NSEvent.mouseLocation
        if expanded {
            if !window.frame.insetBy(dx: -30, dy: -30).contains(mouse) {
                collapse()
            }
        } else {
            let trigger = NSRect(
                x: screen.frame.midX - 110,
                y: screen.frame.maxY - 16,
                width: 220,
                height: 16
            )
            if trigger.contains(mouse) {
                expand()
            }
        }
    }

    private func expand() {
        guard let window else { return }
        expanded = true
        window.ignoresMouseEvents = false
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            window.animator().alphaValue = 1
        }
    }

    private func collapse() {
        guard let window else { return }
        expanded = false
        window.ignoresMouseEvents = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            window.animator().alphaValue = 0
        }
    }
}

struct NotchIslandView: View {
    @ObservedObject var model: NowPlayingModel
    let commands: PlayerCommands

    var body: some View {
        HStack(spacing: 12) {
            artworkThumb

            VStack(alignment: .leading, spacing: 3) {
                Text(model.track?.name ?? "Nothing playing")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(model.track?.artist ?? "Open Spotify and press play")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    ProgressView(value: model.estimatedProgress(at: timeline.date))
                        .progressViewStyle(.linear)
                        .tint(.white.opacity(0.8))
                        .controlSize(.small)
                }
            }

            Spacer(minLength: 4)

            HStack(spacing: 12) {
                controlButton("backward.fill", action: commands.previous)
                controlButton(model.status?.isPlaying == true ? "pause.fill" : "play.fill", action: commands.playPause)
                controlButton("forward.fill", action: commands.next)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(width: 360, height: 88)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.black.opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(.white.opacity(0.1))
        )
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var artworkThumb: some View {
        Group {
            if let artwork = model.artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Color(white: 0.15)
                    Image(systemName: "music.note")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 54, height: 54)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func controlButton(_ symbolName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbolName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
