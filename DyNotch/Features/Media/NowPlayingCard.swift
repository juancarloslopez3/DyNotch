import SwiftUI

/// Home-tab media player: artwork, title, scrubber and glass transport controls.
struct NowPlayingCard: View {
    @Environment(AppServices.self) private var services
    /// Shorter: smaller artwork and controls, and no times by the scrubber. With about half the
    /// column: the song and a play button on one row, over the scrubber.
    var height = HomeCardHeight.full

    var body: some View {
        let media = services.media
        let isHalf = height == .half
        GlassCard(padding: isHalf ? 10 : 12, tint: services.settings.tintWithArtwork && media.nowPlaying != nil ? media.artworkColor : nil) {
            if let info = media.nowPlaying {
                if isHalf {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            artwork(size: 36, cornerRadius: 8, iconSize: 14)
                            titles(info, size: 13)
                            PlayPauseButton(isPlaying: info.isPlaying)
                        }
                        Spacer(minLength: 0)
                        PlaybackScrubber(info: info, tint: media.artworkColor, showsTimes: false) { media.seek(to: $0) }
                    }
                } else {
                    let isShort = height == .short
                    VStack(alignment: .leading, spacing: isShort ? 8 : 10) {
                        HStack(spacing: 12) {
                            artwork(size: isShort ? 44 : 58, cornerRadius: isShort ? 10 : 12, iconSize: isShort ? 16 : 20)
                            titles(info, size: 14)
                        }

                        Spacer(minLength: 0)

                        PlaybackScrubber(info: info, tint: media.artworkColor, showsTimes: !isShort) { media.seek(to: $0) }

                        TransportControls(isPlaying: info.isPlaying, isCompact: isShort)
                            .frame(maxWidth: .infinity)
                    }
                }
            } else {
                NothingPlayingView(isAvailable: media.isAvailable, isCompact: isHalf, player: media.musicPlayer) {
                    media.openMusicPlayer()
                }
            }
        }
    }

    /// The cover, with the playing app's icon on its corner to switch to it.
    private func artwork(size: CGFloat, cornerRadius: CGFloat, iconSize: CGFloat) -> some View {
        let media = services.media
        return CoverArtView(image: media.artwork, cover: media.cover, size: size, cornerRadius: cornerRadius)
            .overlay(alignment: .bottomTrailing) {
                if let icon = media.appIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: iconSize, height: iconSize)
                        .offset(x: iconSize * 0.3, y: iconSize * 0.3)
                        .onTapGesture { media.openSourceApp() }
                        .help(media.appName.map { String(localized: "Open \($0)") } ?? String(localized: "Open app"))
                }
            }
    }

    /// The song and the artist, sliding the way a skip went when the track changes.
    private func titles(_ info: NowPlayingInfo, size: CGFloat) -> some View {
        let media = services.media
        return ZStack(alignment: .leading) {
            VStack(alignment: .leading, spacing: 2) {
                Text(media.title(of: info))
                    .font(.system(size: size, weight: .semibold))
                    .lineLimit(1)
                Text(media.subtitle(of: info))
                    .font(.system(size: size - 2))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .id(info.trackKey)
            .transition(TrackTitleTransition(change: media.trackChange))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: info.trackKey)
    }
}

struct ArtworkView: View {
    let image: NSImage?
    let size: CGFloat
    let cornerRadius: CGFloat

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Color.white.opacity(0.1)
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.4, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: cornerRadius))
    }
}

private struct TransportControls: View {
    @Environment(AppServices.self) private var services
    let isPlaying: Bool
    var isCompact = false

    var body: some View {
        let media = services.media
        let skip = isCompact ? CGSize(width: 28, height: 18) : CGSize(width: 30, height: 22)
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                Button { media.previousTrack() } label: {
                    Image(systemName: "backward.fill").frame(width: skip.width, height: skip.height)
                }
                Button { media.togglePlayPause() } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: isCompact ? 34 : 38, height: isCompact ? 22 : 26)
                }
                Button { media.nextTrack() } label: {
                    Image(systemName: "forward.fill").frame(width: skip.width, height: skip.height)
                }
            }
            .font(.system(size: 14, weight: .semibold))
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
        }
    }
}

/// Play or pause on its own, for a card with room for little else.
private struct PlayPauseButton: View {
    @Environment(AppServices.self) private var services
    let isPlaying: Bool

    var body: some View {
        Button { services.media.togglePlayPause() } label: {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 34, height: 22)
        }
        .font(.system(size: 14, weight: .semibold))
        .buttonStyle(.glass)
        .buttonBorderShape(.capsule)
        .help(isPlaying ? "Pause" : "Play")
    }
}

/// Progress bar with elapsed / remaining time; drag to seek.
private struct PlaybackScrubber: View {
    let info: NowPlayingInfo
    let tint: Color
    var showsTimes = true
    let onSeek: (TimeInterval) -> Void
    @State private var dragPosition: TimeInterval?

    var body: some View {
        TimelineView(.aligned(every: 0.5)) { context in
            let duration = info.duration ?? 0
            let position = dragPosition ?? info.position(at: context.date)
            VStack(spacing: 3) {
                LevelBar(level: duration > 0 ? Float(position / duration) : 0, tint: .white) { fraction in
                    guard duration > 0 else { return }
                    dragPosition = Double(fraction) * duration
                    seekDebounced()
                }
                .frame(height: 5)
                .disabled(duration == 0)
                if showsTimes {
                    HStack {
                        Text(Self.format(position))
                        Spacer()
                        Text("-" + Self.format(max(duration - position, 0)))
                    }
                    .font(.system(size: 9, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    @State private var seekTask: Task<Void, Never>?

    private func seekDebounced() {
        seekTask?.cancel()
        seekTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let position = dragPosition else { return }
            onSeek(position)
            try? await Task.sleep(for: .milliseconds(600))
            dragPosition = nil
        }
    }

    static func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.down))
        return total >= 3600
            ? String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60)
            : String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// The artwork, the song and a play/pause button on one row; just the artwork and the button
/// when it's narrow.
struct NowPlayingSmallCard: View {
    @Environment(AppServices.self) private var services
    let isNarrow: Bool

    var body: some View {
        let media = services.media
        SmallWidgetCard(tint: services.settings.tintWithArtwork && media.nowPlaying != nil ? media.artworkColor : nil) {
            if let info = media.nowPlaying {
                HStack(spacing: isNarrow ? 6 : 8) {
                    CoverArtView(image: media.artwork, cover: media.cover, size: 26, cornerRadius: 6)
                        .help(isNarrow ? [media.title(of: info), info.artist].filter { !$0.isEmpty }.joined(separator: " — ") : "")
                    if !isNarrow {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(media.title(of: info))
                                .font(.system(size: 11.5, weight: .semibold))
                            Text(media.subtitle(of: info))
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Button { media.togglePlayPause() } label: {
                        Image(systemName: info.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .contentTransition(.symbolEffect(.replace))
                            .frame(width: 26, height: 26)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .help(info.isPlaying ? "Pause" : "Play")
                }
            } else {
                SmallEmptyState(
                    symbol: media.isAvailable ? "music.note" : "exclamationmark.triangle",
                    text: media.isAvailable ? "Nothing Playing" : "Media info unavailable",
                    isNarrow: isNarrow
                )
            }
        }
    }
}

private struct NothingPlayingView: View {
    let isAvailable: Bool
    /// The symbol beside the rest, for a card about half the column high.
    var isCompact = false
    let player: MusicPlayer
    let openPlayer: () -> Void

    var body: some View {
        Group {
            if isCompact {
                HStack(spacing: 12) {
                    symbol
                    VStack(alignment: .leading, spacing: 6) {
                        message
                        button
                    }
                }
            } else {
                VStack(spacing: 10) {
                    symbol
                    message
                    button
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var symbol: some View {
        Image(systemName: isAvailable ? "music.note" : "exclamationmark.triangle")
            .font(.system(size: isCompact ? 22 : 26, weight: .medium))
            .foregroundStyle(.white.opacity(0.5))
    }

    private var message: some View {
        Text(isAvailable ? "Nothing Playing" : "Media info unavailable")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    @ViewBuilder
    private var button: some View {
        if isAvailable {
            Button("Open \(player.title)", action: openPlayer)
                .buttonStyle(.glass)
                .controlSize(.small)
        }
    }
}

/// The waveform beside the notch, like the one in the iPhone's Dynamic Island: it moves with
/// the music actually playing (a stand-in rhythm until DyNotch can hear system audio) and
/// settles into a row of dots when playback stops. One gradient runs across all the bars.
struct AudioBars: View {
    @Environment(AppServices.self) private var services
    let isPlaying: Bool
    var colors: [Color] = [.white]

    // Proportioned against the album art like the iPhone's.
    private static let barWidth: CGFloat = 2.2
    private static let spacing: CGFloat = 1.8
    private static let height: CGFloat = 14
    private static let count = SpectrumAnalyzer.bandCount
    /// Width of the whole waveform.
    static let width = CGFloat(count) * barWidth + CGFloat(count - 1) * spacing

    /// When the bars started rising out of the dots; `nil` while they rest.
    @State private var risingSince: Date?

    var body: some View {
        let meter = services.media.meter
        TimelineView(.animation(paused: !isPlaying)) { context in
            let levels = isPlaying ? meter.currentLevels() ?? Self.standIn(at: context.date) : []
            let rise = Self.rise(since: isPlaying ? risingSince : nil, at: context.date)
            LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
                .mask {
                    HStack(spacing: Self.spacing) {
                        ForEach(0..<Self.count, id: \.self) { index in
                            let level = index < levels.count ? levels[index] * rise : 0
                            Capsule()
                                .frame(width: Self.barWidth, height: Self.barWidth + (Self.height - Self.barWidth) * CGFloat(level))
                        }
                    }
                }
        }
        .frame(width: Self.width, height: Self.height)
        .opacity(isPlaying ? 1 : 0.85)
        // Settling into dots is animated here; rising is eased frame by frame in `rise`.
        .animation(.smooth(duration: 0.6), value: isPlaying)
        .onChange(of: isPlaying, initial: true) { risingSince = isPlaying ? .now : nil }
        .onAppear { services.media.meter.barsAppeared() }
        .onDisappear { services.media.meter.barsDisappeared() }
    }

    private static func rise(since start: Date?, at date: Date) -> Float {
        guard let start else { return 0 }
        let progress = Float(min(max(date.timeIntervalSince(start) / 0.5, 0), 1))
        return progress * progress * (3 - 2 * progress)
    }

    /// Levels that move like music, for when the real audio can't be heard: a ~120 bpm pulse
    /// strongest in the middle, over a drift that differs bar to bar.
    static func standIn(at date: Date) -> [Float] {
        let time = date.timeIntervalSinceReferenceDate
        let beat = pow(0.5 + 0.5 * cos(time * .pi * 4), 6)
        return (0..<count).map { index in
            let position = Double(index) - Double(count - 1) / 2
            let centre = 1 - abs(position) / Double(count)
            let drift = 0.5 * sin(time * (6.3 + Double(index) * 1.7) + Double(index) * 2.1)
                + 0.3 * sin(time * (10.9 - Double(index) * 0.8) + Double(index) * 0.7)
            return Float(min(max(centre * (0.45 + 0.3 * drift) + 0.35 * beat * centre, 0.08), 1))
        }
    }
}
