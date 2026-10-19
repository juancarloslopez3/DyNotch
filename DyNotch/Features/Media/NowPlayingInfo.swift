import Foundation

/// A snapshot of what is playing, parsed from the mediaremote-adapter JSON payload
/// (`stream --micros`).
nonisolated struct NowPlayingInfo: Equatable, Sendable {
    var title: String
    var artist: String
    var album: String
    var duration: TimeInterval?
    /// Elapsed time measured at `timestamp`.
    var elapsed: TimeInterval?
    var timestamp: Date?
    var playbackRate: Double
    var isPlaying: Bool
    var bundleIdentifier: String?
    var artworkData: Data?

    /// Identity of the track, used to detect song changes.
    var trackKey: String { "\(title)\u{1F}\(artist)\u{1F}\(album)" }

    init?(payload: [String: Any], artworkData: Data?) {
        // Safari's private windows still report what plays, with the title, artist and album
        // blanked. A payload without the key at all is only the app and its playing state,
        // which the adapter (`--allow-missing-title`) sends ahead of the rest.
        guard let title = payload["title"] as? String else { return nil }
        self.title = title
        artist = payload["artist"] as? String ?? ""
        album = payload["album"] as? String ?? ""
        duration = Self.seconds(payload["durationMicros"]) ?? (payload["duration"] as? Double)
        elapsed = Self.seconds(payload["elapsedTimeMicros"]) ?? (payload["elapsedTime"] as? Double)
        if let micros = (payload["timestampEpochMicros"] as? NSNumber)?.doubleValue {
            timestamp = Date(timeIntervalSince1970: micros / 1_000_000)
        } else {
            timestamp = nil
        }
        isPlaying = payload["playing"] as? Bool ?? false
        playbackRate = (payload["playbackRate"] as? NSNumber)?.doubleValue ?? (isPlaying ? 1 : 0)
        // Browsers report a helper process; the parent is the app the user knows.
        bundleIdentifier = payload["parentApplicationBundleIdentifier"] as? String
            ?? payload["bundleIdentifier"] as? String
        self.artworkData = artworkData
    }

    /// Estimated playback position at `date`.
    func position(at date: Date) -> TimeInterval {
        guard var position = elapsed else { return 0 }
        if isPlaying, let timestamp {
            position += date.timeIntervalSince(timestamp) * max(playbackRate, 0)
        }
        if let duration, duration > 0 { position = min(position, duration) }
        return max(position, 0)
    }

    private static func seconds(_ value: Any?) -> TimeInterval? {
        (value as? NSNumber).map { $0.doubleValue / 1_000_000 }
    }
}

/// Folds the adapter's stream of full and diff messages into the current payload.
nonisolated struct NowPlayingStreamState {
    private(set) var payload: [String: Any] = [:]
    private(set) var artworkData: Data?

    /// Applies one JSON line received at `date`. Returns `false` if the line wasn't a data message.
    mutating func apply(line: String, at date: Date = .now) -> Bool {
        guard let data = line.data(using: .utf8),
              let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              message["type"] as? String == "data"
        else { return false }

        let incoming = message["payload"] as? [String: Any] ?? [:]
        let isDiff = message["diff"] as? Bool ?? false
        if isDiff {
            let wasPlaying = payload["playing"] as? Bool ?? false
            let reached = wasPlaying ? info?.position(at: date) : nil
            for (key, value) in incoming {
                payload[key] = value is NSNull ? nil : value
            }
            // The playing flag comes from its own notification, and some players (Spotify)
            // don't restamp the position on resuming. The paused position would then run on
            // from the moment it paused, as if the track had played all along.
            if !wasPlaying, payload["playing"] as? Bool == true, incoming["timestampEpochMicros"] == nil {
                payload["timestampEpochMicros"] = date.timeIntervalSince1970 * 1_000_000
            }
            // Pausing, the flag likewise arrives ahead of the player's new position. Until that
            // follows, the position last stamped (often where playback last started) would
            // show, sending the progress bar back and then forward again.
            if let reached, payload["playing"] as? Bool == false, incoming["elapsedTimeMicros"] == nil {
                payload["elapsedTimeMicros"] = reached * 1_000_000
                payload["timestampEpochMicros"] = date.timeIntervalSince1970 * 1_000_000
            }
        } else {
            payload = incoming
        }
        if !isDiff || incoming.keys.contains("artworkData") {
            artworkData = (payload["artworkData"] as? String).flatMap { Data(base64Encoded: $0) }
        }
        return true
    }

    var info: NowPlayingInfo? { NowPlayingInfo(payload: payload, artworkData: artworkData) }
}

/// How one track gave way to the next.
nonisolated enum TrackChange: Equatable, Sendable {
    /// The previous track played to its end and the player moved on by itself.
    case continued
    /// The user moved to another track: skipped either way, or started something new.
    case skipped(forward: Bool)
}

/// Tells a track that played out from one the user skipped, so a song ending can be shown
/// quietly while a skip gets the full peek.
nonisolated struct TrackChangeDetector {
    /// A change this close to the end of the outgoing track counts as it playing out
    /// (leaves room for crossfades and the stream's delay).
    static let endTolerance: TimeInterval = 6
    /// How long a skip command stays attributable to the next track change.
    static let skipWindow: TimeInterval = 4
    /// Players sometimes report nothing for a moment between tracks.
    static let gapTolerance: TimeInterval = 2

    private var track: NowPlayingInfo?
    /// Furthest position `track` reached, so a player resetting the elapsed time just
    /// before switching tracks still counts as having played to the end.
    private var furthest: TimeInterval = 0
    private var stoppedAt: Date?
    private var skip: (forward: Bool, date: Date)?

    /// Records a skip command (ours or a media key) for the change it is about to cause.
    mutating func noteSkip(forward: Bool, at date: Date) {
        skip = (forward, date)
    }

    /// Feed every update. Returns how the track changed, or `nil` if it didn't.
    mutating func update(_ info: NowPlayingInfo?, at date: Date) -> TrackChange? {
        if let track, stoppedAt == nil {
            furthest = max(furthest, track.position(at: date))
        }
        guard let info else {
            if stoppedAt == nil { stoppedAt = date }
            return nil
        }
        let previous = track
        let gap = stoppedAt.map { date.timeIntervalSince($0) } ?? 0
        track = info
        stoppedAt = nil

        guard let previous, gap <= Self.gapTolerance else {
            furthest = 0
            skip = nil
            return .skipped(forward: true)
        }
        guard info.trackKey != previous.trackKey else { return nil }

        let reached = furthest
        furthest = 0
        defer { skip = nil }
        if let skip, date.timeIntervalSince(skip.date) <= Self.skipWindow {
            return .skipped(forward: skip.forward)
        }
        // Without a length (radio, some web players) there is no telling; stay quiet.
        guard let duration = previous.duration, duration > 0, duration - reached > Self.endTolerance else {
            return .continued
        }
        // Moved on mid-song without a command from us: skipped in the player, from a headset, ...
        return .skipped(forward: true)
    }
}
