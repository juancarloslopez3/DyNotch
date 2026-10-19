import SwiftUI

/// Album art that turns over to the next track's cover: flipped in place like a card when the
/// song played out, slid aside Cover Flow–style in the skip direction when the user skipped.
struct CoverArtView: View {
    let image: NSImage?
    let cover: CoverChange
    let size: CGFloat
    let cornerRadius: CGFloat

    /// The change being animated; `turns` restarts the animation.
    @State private var turn: CoverChange?
    @State private var turns = 0

    var body: some View {
        let change = turn?.change ?? .continued
        let outgoing = turn.map { ArtworkView(image: $0.previous, size: size, cornerRadius: cornerRadius) }
        let travel = size * 0.7
        ArtworkView(image: image, size: size, cornerRadius: cornerRadius)
            .keyframeAnimator(initialValue: 1.0, trigger: turns) { content, progress in
                ZStack {
                    if let outgoing, progress < 1 {
                        outgoing
                            .modifier(CoverFace(change: change, progress: progress, isOutgoing: true, travel: travel))
                    }
                    content
                        .modifier(CoverFace(change: change, progress: progress, isOutgoing: false, travel: travel))
                }
            } keyframes: { _ in
                KeyframeTrack {
                    MoveKeyframe(0.0)
                    SpringKeyframe(1.0, spring: change == .continued
                        ? Spring(duration: 0.7, bounce: 0.15)
                        : Spring(duration: 0.5, bounce: 0.12))
                }
            }
            .onChange(of: cover.revision) { startTurn() }
            .onAppear {
                // Shown because of the change (e.g. the song-change peek): play it here too.
                if cover.date.timeIntervalSinceNow > -0.4 { startTurn() }
            }
    }

    private func startTurn() {
        turn = cover
        turns += 1
    }
}

/// One cover part-way through a change; `progress` runs from 0 (old cover) to 1 (new cover).
private struct CoverFace: ViewModifier {
    let change: TrackChange
    let progress: Double
    let isOutgoing: Bool
    /// How far a skipped cover slides aside.
    let travel: CGFloat

    func body(content: Content) -> some View {
        switch change {
        case .continued:
            // A card turning over: the old cover is its front, the new one its back.
            let angle = progress * 180 - (isOutgoing ? 0 : 180)
            let edgeOn = sin(min(max(progress, 0), 1) * .pi)
            content
                .brightness(-0.3 * edgeOn)
                .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
                .opacity((progress < 0.5) == isOutgoing ? 1 : 0)
        case .skipped(let forward):
            // The old cover slides off angled away, the new one comes in from the other side.
            let side: Double = forward ? -1 : 1
            // 0 is centred, ±1 is off to the side.
            let position = isOutgoing ? progress : progress - 1
            let distance = min(abs(position), 1)
            content
                .rotation3DEffect(.degrees(-side * 50 * position), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
                .scaleEffect(1 - 0.25 * distance)
                .offset(x: side * travel * position)
                .opacity(1 - distance)
        }
    }
}

/// Swaps track titles: the new one slides in from the skip side while the old one fades in place.
struct TrackTitleTransition: Transition {
    var change: TrackChange

    func body(content: Content, phase: TransitionPhase) -> some View {
        content
            .offset(x: phase == .willAppear ? change.titleOffset : 0)
            .opacity(phase.isIdentity ? 1 : 0)
            .blur(radius: phase.isIdentity ? 0 : 3)
    }
}

extension TrackChange {
    /// Where the next title slides in from.
    var titleOffset: CGFloat {
        switch self {
        case .continued: 0
        case .skipped(let forward): forward ? 18 : -18
        }
    }
}
