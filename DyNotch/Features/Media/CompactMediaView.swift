import SwiftUI

/// Album art on the left of the notch, the waveform on the right.
struct CompactMediaView: View {
    @Environment(AppServices.self) private var services
    let notch: CGSize
    var isHovering = false

    var body: some View {
        let media = services.media
        WingsLayout(notch: notch) {
            CompactCoverView(size: notch.height - 10, cornerRadius: 6)
        } trailing: {
            AudioBars(isPlaying: media.isPlaying, colors: media.artworkGradient)
                .scaleEffect(isHovering ? 1.2 : 1)
        }
    }
}

/// The album art beside the notch, or alone in a bubble beside it. While the music is stopped
/// (the few seconds before it folds away) the art shrinks and dims, like the Dynamic Island's.
struct CompactCoverView: View {
    @Environment(AppServices.self) private var services
    let size: CGFloat
    let cornerRadius: CGFloat

    var body: some View {
        let media = services.media
        let isPlaying = media.isPlaying
        CoverArtView(image: media.artwork, cover: media.cover, size: size, cornerRadius: cornerRadius)
            .saturation(isPlaying ? 1 : 0.75)
            .brightness(isPlaying ? 0 : -0.1)
            .scaleEffect(isPlaying ? 1 : 0.8)
            .animation(.smooth(duration: 0.6), value: isPlaying)
    }
}

/// Skip peek, laid out like the iPhone's expanded Dynamic Island: a large cover hanging from the
/// left ear, the title and artist beside it under the notch, and the equalizer at the far end.
/// The cover slides over in the skip direction, a skip glyph nudges the same way before the bars
/// return, and the title follows from that side.
struct NowPlayingActivityView: View {
    @Environment(AppServices.self) private var services
    let title: String
    let artist: String
    let forward: Bool
    let notch: CGSize

    /// Side length of the cover.
    static let coverSize: CGFloat = 52
    /// Margin around the content. Keeps the cover's corners concentric with the shape's.
    static let inset: CGFloat = 14

    @State private var showsTitle = false
    @State private var showsBars = false
    @State private var nudge = 0

    private var change: TrackChange { .skipped(forward: forward) }

    var body: some View {
        let media = services.media
        HStack(alignment: .bottom, spacing: 12) {
            CoverArtView(image: media.artwork, cover: media.cover, size: Self.coverSize, cornerRadius: 10)
                .overlay(alignment: .bottomTrailing) {
                    if let icon = media.appIcon {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 18, height: 18)
                            .offset(x: 5, y: 5)
                    }
                }

            HStack(spacing: 12) {
                ZStack(alignment: .leading) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title)
                            .font(.system(size: 14, weight: .semibold))
                        if !artist.isEmpty {
                            Text(artist)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .lineLimit(1)
                    .id(title + "\u{1F}" + artist)
                    .transition(TrackTitleTransition(change: change))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .offset(x: showsTitle ? 0 : change.titleOffset)
                .opacity(showsTitle ? 1 : 0)
                .blur(radius: showsTitle ? 0 : 3)

                ZStack {
                    if showsBars {
                        AudioBars(isPlaying: media.isPlaying, colors: media.artworkGradient)
                            .transition(.blurReplace)
                    } else {
                        Image(systemName: forward ? "forward.fill" : "backward.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(media.artworkColor)
                            .symbolEffect(forward ? .wiggle.forward : .wiggle.backward, value: nudge)
                            .transition(.blurReplace)
                    }
                }
                .frame(width: AudioBars.width)
            }
        }
        .padding([.horizontal, .bottom], Self.inset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .task(id: title + "\u{1F}" + artist) {
            withAnimation(.smooth(duration: 0.25)) { showsBars = false }
            if !showsTitle {
                // Let the shape start growing before the title arrives.
                withAnimation(.spring(response: 0.45, dampingFraction: 0.85).delay(0.08)) { showsTitle = true }
            }
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            nudge += 1
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }
            withAnimation(.smooth(duration: 0.35)) { showsBars = true }
        }
    }
}
