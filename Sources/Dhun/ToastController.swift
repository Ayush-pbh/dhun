import AppKit
import SwiftUI

/// A brief, elegant "now playing" toast that fades in at the top-center of
/// the screen when the track changes, then fades away.
final class ToastController {
    private var window: NSWindow?
    private var hideTimer: Timer?

    func show(track: TrackInfo, artwork: NSImage?) {
        guard let screen = NSScreen.main else { return }
        hideTimer?.invalidate()

        let hosting = NSHostingView(rootView: ToastView(track: track, artwork: artwork))
        let size = hosting.fittingSize
        let frame = NSRect(
            x: screen.frame.midX - size.width / 2,
            y: screen.visibleFrame.maxY - size.height - 16,
            width: size.width,
            height: size.height
        )

        let w: NSWindow
        if let window {
            w = window
        } else {
            w = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
            w.isOpaque = false
            w.backgroundColor = .clear
            w.hasShadow = false
            w.level = .statusBar
            w.ignoresMouseEvents = true
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            w.isReleasedWhenClosed = false
            window = w
        }

        w.setFrame(frame, display: false)
        w.contentView = hosting
        w.alphaValue = 0
        w.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            w.animator().alphaValue = 1
        }

        hideTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
            self?.dismiss()
        }
    }

    private func dismiss() {
        guard let window else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.4
            window.animator().alphaValue = 0
        }, completionHandler: {
            window.orderOut(nil)
        })
    }
}

struct ToastView: View {
    let track: TrackInfo
    let artwork: NSImage?

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let artwork {
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
            .frame(width: 40, height: 40)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(track.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(track.artist)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .frame(maxWidth: 340)
        .background(.black.opacity(0.88), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.12))
        )
        .preferredColorScheme(.dark)
    }
}
