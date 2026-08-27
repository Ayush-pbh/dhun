import AppKit

struct TrackInfo: Equatable {
    var name: String
    var artist: String
    var album: String
    var artworkURL: URL?
    var isPlaying: Bool
}

struct PlaybackStatus: Equatable {
    var isPlaying: Bool
    /// Seconds into the track.
    var position: Double
    /// Track length in seconds.
    var duration: Double
    /// Spotify's own volume, 0–100.
    var volume: Int
}

/// Polls the Spotify desktop app over Apple events for the current track and
/// playback status, fetches album artwork, and sends playback commands.
/// Listens for Spotify's playback-changed distributed notification so track
/// changes show up immediately.
final class SpotifyController: NSObject {
    /// Fired when the track identity changes. The URL is the artwork URL the
    /// delivered image actually corresponds to (it can briefly lag the track
    /// while the new artwork downloads).
    var onUpdate: ((TrackInfo?, NSImage?, URL?) -> Void)?
    /// Fired on every poll with fresh position/duration/volume.
    var onStatus: ((PlaybackStatus?) -> Void)?
    var onPermissionProblem: (() -> Void)?

    private static let spotifyBundleID = "com.spotify.client"

    private var timer: Timer?
    private var lastDelivered: TrackInfo?
    private var didDeliverInitial = false
    private var artworkCache: (url: URL, image: NSImage)?
    private var reportedPermissionProblem = false
    private var commandScripts: [String: NSAppleScript] = [:]

    private let script = NSAppleScript(source: """
        set output to {}
        if application "Spotify" is running then
            tell application "Spotify"
                if player state is playing or player state is paused then
                    set t to current track
                    set output to {name of t, artist of t, album of t, artwork url of t, ¬
                        (player state is playing), player position, duration of t, sound volume}
                end if
            end tell
        end if
        return output
        """)

    func start() {
        poll()
        let t = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.poll()
        }
        t.tolerance = 0.5
        timer = t

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(playbackChanged),
            name: Notification.Name("com.spotify.client.PlaybackStateChanged"),
            object: nil
        )
    }

    // MARK: - Commands

    func playPause() { run("playpause") }
    func nextTrack() { run("next track") }
    func previousTrack() { run("previous track") }
    func setVolume(_ volume: Int) { run("set sound volume to \(max(0, min(100, volume)))") }

    private func run(_ command: String) {
        guard spotifyIsRunning else { return }
        let source = "tell application \"Spotify\" to \(command)"
        let commandScript: NSAppleScript
        if let cached = commandScripts[source] {
            commandScript = cached
        } else {
            guard let fresh = NSAppleScript(source: source) else { return }
            commandScripts[source] = fresh
            commandScript = fresh
        }
        var errorInfo: NSDictionary?
        commandScript.executeAndReturnError(&errorInfo)
        // Refresh quickly so the UI reflects the command.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.poll()
        }
    }

    // MARK: - Polling

    @objc private func playbackChanged(_ note: Notification) {
        poll()
    }

    private var spotifyIsRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: Self.spotifyBundleID).isEmpty
    }

    private func poll() {
        // Never send Apple events unless Spotify is already running,
        // otherwise the "tell" would launch it.
        guard spotifyIsRunning, let script else {
            onStatus?(nil)
            deliver(nil)
            return
        }

        var errorInfo: NSDictionary?
        let result = script.executeAndReturnError(&errorInfo)

        if let errorInfo {
            let code = errorInfo["NSAppleScriptErrorNumber"] as? Int ?? 0
            if code == -1743, !reportedPermissionProblem {
                reportedPermissionProblem = true
                onPermissionProblem?()
            }
            onStatus?(nil)
            deliver(nil)
            return
        }

        guard result.numberOfItems >= 8,
              let name = result.atIndex(1)?.stringValue,
              let artist = result.atIndex(2)?.stringValue,
              let album = result.atIndex(3)?.stringValue else {
            onStatus?(nil)
            deliver(nil)
            return
        }

        let isPlaying = result.atIndex(5)?.booleanValue ?? false
        let track = TrackInfo(
            name: name,
            artist: artist,
            album: album,
            artworkURL: URL(string: result.atIndex(4)?.stringValue ?? ""),
            isPlaying: isPlaying
        )
        let status = PlaybackStatus(
            isPlaying: isPlaying,
            position: result.atIndex(6)?.doubleValue ?? 0,
            duration: Double(result.atIndex(7)?.int32Value ?? 0) / 1000,
            volume: Int(result.atIndex(8)?.int32Value ?? 0)
        )
        onStatus?(status)
        deliver(track)
    }

    private func deliver(_ track: TrackInfo?) {
        guard track != lastDelivered || !didDeliverInitial else { return }
        didDeliverInitial = true
        lastDelivered = track

        guard let track, let url = track.artworkURL else {
            onUpdate?(track, nil, nil)
            return
        }

        if let cached = artworkCache, cached.url == url {
            onUpdate?(track, cached.image, cached.url)
            return
        }

        // Keep showing the previous artwork while the new one downloads.
        onUpdate?(track, artworkCache?.image, artworkCache?.url)

        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let image = NSImage(data: data) else { return }
            DispatchQueue.main.async {
                guard let self else { return }
                self.artworkCache = (url, image)
                if self.lastDelivered == track {
                    self.onUpdate?(track, image, url)
                }
            }
        }.resume()
    }
}
