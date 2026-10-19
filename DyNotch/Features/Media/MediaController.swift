import AppKit
import Observation
import SwiftUI

/// The latest switch of the shown artwork to another track's cover.
struct CoverChange {
    var revision = 0
    var change = TrackChange.continued
    /// The cover shown before, which views turn away.
    var previous: NSImage?
    var date = Date.distantPast
}

/// Now-playing state for any app (Music, Spotify, browsers, ...).
///
/// macOS 15.4+ only lets entitled processes read MediaRemote, so this runs the bundled
/// mediaremote-adapter through `/usr/bin/perl` (which is entitled) and parses its output.
@Observable
final class MediaController {
    /// How long the player beside the notch stays up after the music stops.
    static let holdDuration: Duration = .seconds(3)

    private(set) var nowPlaying: NowPlayingInfo? {
        didSet { if isPlaying != (oldValue?.isPlaying ?? false) { playbackChanged() } }
    }
    private(set) var artwork: NSImage?
    private(set) var artworkColor: Color = .white
    /// The artwork's colors from its left half to its right, which the waveform beside the
    /// notch fades between like the Dynamic Island's.
    private(set) var artworkGradient: [Color] = [.white, .white]
    private(set) var appIcon: NSImage?
    private(set) var appName: String?
    /// Whether the source app files itself under Music in its Info.plist (Music, Spotify, ...).
    /// Browsers and video players don't, and get only the quiet track-change treatment.
    @ObservationIgnored private var isMusicApp = false
    /// How the current track took over from the previous one.
    private(set) var trackChange = TrackChange.continued
    /// Bumped when the artwork switches to the next track's, so views can turn the cover over.
    private(set) var cover = CoverChange()
    /// `false` if the adapter can't run on this system.
    private(set) var isAvailable = true

    var isPlaying: Bool { nowPlaying?.isPlaying ?? false }
    /// Playing, or stopped less than `holdDuration` ago. Like the Dynamic Island, the player
    /// beside the notch stays for a moment when the music stops, its bars settled into dots,
    /// before it folds away; resuming in the meantime picks up where it was.
    private(set) var isActive = false

    /// Levels of the audio actually playing, for the bars beside the notch.
    @ObservationIgnored let meter = AudioLevelMeter()

    @ObservationIgnored private weak var services: AppServices?
    @ObservationIgnored private var process: Process?
    @ObservationIgnored private var readTask: Task<Void, Never>?
    @ObservationIgnored private var restartDelay: Duration = .seconds(1)
    @ObservationIgnored private var lastArtworkData: Data?
    @ObservationIgnored private var hasReceivedFirstUpdate = false
    @ObservationIgnored private var trackChanges = TrackChangeDetector()
    @ObservationIgnored private var coverWait: Task<Void, Never>?
    @ObservationIgnored private var holdTask: Task<Void, Never>?
    /// The cover found for media that came without one (a video in Safari), for the track it
    /// was found for.
    @ObservationIgnored private var foundCover: (trackKey: String, data: Data)?
    /// What the latest cover search was for, and the search while it runs.
    @ObservationIgnored private var coverSearchKey: String?
    @ObservationIgnored private var coverSearch: Task<Void, Never>?

    private enum Command: Int {
        case play = 0, pause = 1, togglePlayPause = 2, nextTrack = 4, previousTrack = 5
    }

    private struct AdapterPaths: Sendable {
        let script: String
        let framework: String
    }

    private var adapterPaths: AdapterPaths? {
        guard let script = Bundle.main.path(forResource: "mediaremote-adapter", ofType: "pl"),
              let frameworks = Bundle.main.privateFrameworksPath
        else { return nil }
        let framework = (frameworks as NSString).appendingPathComponent("MediaRemoteAdapter.framework")
        guard FileManager.default.fileExists(atPath: framework) else { return nil }
        return AdapterPaths(script: script, framework: framework)
    }

    func start(services: AppServices) {
        self.services = services
        Task {
            await Self.killOrphanedStreams()
            startStream()
        }
    }

    func stop() {
        readTask?.cancel()
        process?.terminationHandler = nil
        process?.terminate()
        process = nil
    }

    /// The adapter doesn't notice when its parent dies, so a crashed or force-quit DyNotch
    /// leaves its stream running. Clean those up (parent is launchd) before starting.
    nonisolated private static func killOrphanedStreams() async {
        await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/ps")
            process.arguments = ["-axo", "pid=,ppid=,command="]
            let pipe = Pipe()
            process.standardOutput = pipe
            guard (try? process.run()) != nil else { return }
            let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            process.waitUntilExit()
            for line in output.split(separator: "\n") {
                let fields = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
                guard fields.count == 3, fields[1] == "1",
                      fields[2].contains("mediaremote-adapter.pl"), fields[2].contains("DyNotch.app"),
                      let pid = pid_t(fields[0])
                else { continue }
                kill(pid, SIGTERM)
            }
        }.value
    }

    // MARK: - Stream

    private func startStream() {
        guard let paths = adapterPaths else {
            isAvailable = false
            return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [paths.script, paths.framework, "stream", "--micros", "--debounce=40", "--allow-missing-title"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [weak self] _ in
            Task { @MainActor in self?.streamEnded() }
        }
        do {
            try process.run()
        } catch {
            isAvailable = false
            return
        }
        self.process = process

        let handle = pipe.fileHandleForReading
        readTask = Task.detached { [weak self] in
            var state = NowPlayingStreamState()
            do {
                for try await line in handle.bytes.lines {
                    guard state.apply(line: line) else { continue }
                    let info = state.info
                    await self?.apply(info)
                }
            } catch {}
        }
    }

    private func streamEnded() {
        process = nil
        readTask?.cancel()
        // Restart with backoff; the adapter exits when e.g. mediaremoted restarts.
        let delay = restartDelay
        restartDelay = min(restartDelay * 2, .seconds(30))
        Task { [weak self] in
            try? await Task.sleep(for: delay)
            self?.startStream()
        }
    }

    private func apply(_ info: NowPlayingInfo?) {
        restartDelay = .seconds(1)
        let previous = nowPlaying
        nowPlaying = info

        let detected = trackChanges.update(info, at: .now)
        let change = hasReceivedFirstUpdate ? detected : nil
        if let change { trackChange = change }

        if let info {
            searchCover(for: info)
            let artworkData = coverData(for: info)
            if artworkData != lastArtworkData || change != nil {
                updateArtwork(artworkData, isNewTrack: change != nil)
            }
        } else if !isActive {
            // While the player is held after the music stopped, its cover stays until it folds away.
            clearArtwork()
        }
        if info?.bundleIdentifier != previous?.bundleIdentifier {
            updateApp(bundleIdentifier: info?.bundleIdentifier)
        }

        if let change, let info, info.isPlaying {
            announce(change, info)
        }
        hasReceivedFirstUpdate = true
    }

    private func updateArtwork(_ data: Data?, isNewTrack: Bool) {
        // Same album: keep the decoded image (unless the one showing is the previous track's).
        let reuse = data != nil && data == lastArtworkData && coverWait == nil
        let image = reuse ? artwork : data.flatMap(NSImage.init(data:))
        lastArtworkData = data
        if isNewTrack, image == nil, artwork != nil || coverSearch != nil {
            // The next cover usually follows the title a moment later (or is being looked up);
            // keep the old one until then so the cover turns over once, straight to the right image.
            coverWait?.cancel()
            coverWait = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(1200))
                guard !Task.isCancelled else { return }
                self?.showArtwork(nil, turnsOver: true)
            }
            return
        }
        showArtwork(image, turnsOver: isNewTrack || coverWait != nil)
    }

    /// The artwork for `info`: its own, else the cover found for it.
    private func coverData(for info: NowPlayingInfo) -> Data? {
        info.artworkData ?? foundCover.flatMap { $0.trackKey == info.trackKey ? $0.data : nil }
    }

    /// Looks for a cover for a browser video, which comes without one. Videos in a private
    /// window share one blank track, so there a new length tells the next one apart; until its
    /// own cover turns up the last one stays. (A titled video keeps its cover through a change
    /// of length, such as an ad giving way to it.)
    private func searchCover(for info: NowPlayingInfo) {
        guard info.artworkData == nil, let app = info.bundleIdentifier, VideoCover.browsers.contains(app) else { return }
        let length = info.title.isEmpty ? info.duration.flatMap { $0.isFinite ? Int($0) : nil } ?? -1 : 0
        let key = "\(app)\u{1F}\(info.trackKey)\u{1F}\(length)"
        guard key != coverSearchKey else { return }
        coverSearchKey = key
        coverSearch?.cancel()
        let title = info.title
        let trackKey = info.trackKey
        coverSearch = Task { [weak self] in
            let data = await VideoCover.find(title: title, app: app)
            guard !Task.isCancelled else { return }
            self?.coverSearchEnded(data, trackKey: trackKey)
        }
    }

    private func coverSearchEnded(_ data: Data?, trackKey: String) {
        coverSearch = nil
        foundCover = data.map { (trackKey, $0) }
        // Another app may have taken over meanwhile, its own cover on the way.
        guard let info = nowPlaying, info.trackKey == trackKey else { return }
        let artworkData = coverData(for: info)
        // Also ends a wait for the cover, turning it over to whatever was found.
        if artworkData != lastArtworkData || coverWait != nil {
            updateArtwork(artworkData, isNewTrack: false)
        }
    }

    private func clearArtwork() {
        lastArtworkData = nil
        showArtwork(nil, turnsOver: false)
    }

    private func showArtwork(_ image: NSImage?, turnsOver: Bool) {
        coverWait?.cancel()
        coverWait = nil
        if turnsOver {
            cover = CoverChange(revision: cover.revision + 1, change: trackChange, previous: artwork, date: .now)
        }
        if image !== artwork {
            artwork = image
            artworkColor = image.flatMap { Self.averageColors(of: $0, columns: 1)?.first } ?? .white
            artworkGradient = image.flatMap { Self.averageColors(of: $0, columns: 2) } ?? [.white, .white]
        }
    }

    // MARK: - Hold

    private func playbackChanged() {
        updateMeter()
        holdTask?.cancel()
        holdTask = nil
        if isPlaying {
            isActive = true
        } else if isActive {
            holdTask = Task { [weak self] in
                try? await Task.sleep(for: Self.holdDuration)
                guard !Task.isCancelled else { return }
                self?.holdEnded()
            }
        }
    }

    private func holdEnded() {
        holdTask = nil
        isActive = false
        // The player quit during the hold: now that the notch has folded, let its cover go too.
        if nowPlaying == nil { clearArtwork() }
    }

    /// Starts or stops listening to system audio for the bars. Call when the setting changes.
    func updateMeter() {
        meter.update(active: isPlaying && services?.settings.barsFollowMusic == true)
    }

    private func announce(_ change: TrackChange, _ info: NowPlayingInfo) {
        guard let services, services.settings.liveSongChange else { return }
        // Don't cover the notch while the user is looking at it, or come up over the video
        // they're watching full screen.
        guard let notch = services.notch.primary, !notch.isOpen, !notch.hidesPlayerInFullScreen else { return }
        // Only music apps get the full peek; a browser or video player starting something is
        // shown like a song that played out.
        let change = isMusicApp ? change : .continued
        // A song that played out is shown quietly: the album art beside the notch (or in its
        // bubble) turns over to the next cover in place. Only when that art isn't showing does a
        // small peek of the same size stand in for it.
        if change == .continued, notch.compactActivity == .media || notch.detachedActivity == .media { return }
        services.activities.post(LiveActivity(
            id: "nowplaying",
            kind: .nowPlaying(title: title(of: info), artist: info.artist, change: change),
            duration: change == .continued ? 2.5 : 3
        ))
    }

    /// The title to show. Media without one (a Safari private window blanks it) goes by its app.
    func title(of info: NowPlayingInfo) -> String {
        info.title.isEmpty ? appName ?? "" : info.title
    }

    /// The line under the title: the artist, else the app, unless the app is the title already.
    func subtitle(of info: NowPlayingInfo) -> String {
        if !info.artist.isEmpty { return info.artist }
        return info.title.isEmpty ? "" : appName ?? ""
    }

    private func updateApp(bundleIdentifier: String?) {
        guard let bundleIdentifier,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
        else {
            appIcon = nil
            appName = nil
            isMusicApp = false
            return
        }
        isMusicApp = Bundle(url: url)?.object(forInfoDictionaryKey: "LSApplicationCategoryType") as? String
            == "public.app-category.music"
        appIcon = NSWorkspace.shared.icon(forFile: url.path)
        appName = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    // MARK: - Commands

    func togglePlayPause() {
        if var info = nowPlaying {
            // Optimistic update; the stream confirms a moment later.
            let position = info.position(at: .now)
            info.isPlaying.toggle()
            info.elapsed = position
            info.timestamp = .now
            nowPlaying = info
        }
        run(["send", String(Command.togglePlayPause.rawValue)])
    }

    func nextTrack() {
        userSkipped(forward: true)
        run(["send", String(Command.nextTrack.rawValue)])
    }

    func previousTrack() {
        userSkipped(forward: false)
        run(["send", String(Command.previousTrack.rawValue)])
    }

    /// Notes a skip the user asked for (our buttons or the keyboard's media keys), so the
    /// track change it causes gets the skip animation in the right direction.
    func userSkipped(forward: Bool) {
        trackChanges.noteSkip(forward: forward, at: .now)
    }

    func seek(to seconds: TimeInterval) {
        if var info = nowPlaying {
            info.elapsed = seconds
            info.timestamp = .now
            nowPlaying = info
        }
        run(["seek", String(Int64(seconds * 1_000_000))])
    }

    func openSourceApp() {
        guard let id = nowPlaying?.bundleIdentifier,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
        else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }

    /// The player chosen in Settings, or Music while that one isn't installed.
    var musicPlayer: MusicPlayer {
        let chosen = services?.settings.musicPlayer ?? .music
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: chosen.bundleIdentifier) != nil ? chosen : .music
    }

    func openMusicPlayer() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: musicPlayer.bundleIdentifier) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }

    private func run(_ arguments: [String]) {
        guard let paths = adapterPaths else { return }
        Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
            process.arguments = [paths.script, paths.framework] + arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try? process.run()
            process.waitUntilExit()
        }
    }

    // MARK: - Artwork color

    /// The artwork's average color in each of `columns` vertical strips, left to right, lifted
    /// to stay visible on black.
    private static func averageColors(of image: NSImage, columns: Int) -> [Color]? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        var pixels = [UInt8](repeating: 0, count: 4 * columns)
        let drawn = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: columns, height: 1, bitsPerComponent: 8, bytesPerRow: 4 * columns,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: columns, height: 1))
            return true
        }
        guard drawn else { return nil }
        return (0..<columns).map { column in
            let red = CGFloat(pixels[column * 4]) / 255
            let green = CGFloat(pixels[column * 4 + 1]) / 255
            let blue = CGFloat(pixels[column * 4 + 2]) / 255
            // Keep the tint visible on black: lift very dark colors and boost saturation a bit.
            var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
            NSColor(red: red, green: green, blue: blue, alpha: 1).getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
            return Color(nsColor: NSColor(hue: hue, saturation: min(saturation * 1.2, 1), brightness: max(brightness, 0.65), alpha: 1))
        }
    }
}
