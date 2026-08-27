import AppKit
import Combine

/// Shared observable state for the SwiftUI surfaces (notch island, ambient
/// mode). The AppDelegate is the single writer.
final class NowPlayingModel: ObservableObject {
    @Published var track: TrackInfo?
    @Published var artwork: NSImage?
    @Published var status: PlaybackStatus?
    @Published var statusDate = Date.distantPast
    @Published var palette = Palette.fallback

    /// Fraction played, interpolated forward from the last poll while playing.
    func estimatedProgress(at date: Date) -> Double {
        guard let status, status.duration > 0 else { return 0 }
        var position = status.position
        if status.isPlaying {
            position += date.timeIntervalSince(statusDate)
        }
        return min(max(position / status.duration, 0), 1)
    }
}

struct PlayerCommands {
    var playPause: () -> Void
    var next: () -> Void
    var previous: () -> Void
}
