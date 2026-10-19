import SwiftUI

/// The second activity going on, in a bubble of its own beside the notch like the Dynamic
/// Island's detached one. It splits off the notch's right end as the activity starts (or the
/// notch closes), and flows back in as it ends (or the notch opens).
///
/// Laid out from `notchEnd` short of the notch's right edge: the bubble forms under the end of
/// the notch, which hides it until it comes out.
struct ActivityBubble: View {
    let activity: CompactActivity?
    let notch: CGSize
    /// The notch's top radius: how far its ears flare.
    let ear: CGFloat
    /// The pointer is over it: it grows a little and its rim lights up, ready for a click.
    let isHovered: Bool
    let open: () -> Void

    /// How far into the notch the bubble's space reaches.
    static let notchEnd: CGFloat = 40

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let activity {
                let size = activity.bubbleSize(notch: notch)
                MinimalActivityView(activity: activity, size: size)
                    .frame(width: size.width, height: size.height)
                    .contentShape(.capsule)
                    .onTapGesture(perform: open)
                    .transition(BubbleSplit(notch: notch, ear: ear, size: size))
                    .id(activity)
            }
        }
        // Room for an oval with some to spare, so a bubble overshooting as it settles isn't cut.
        .frame(width: Self.notchEnd + NotchMetrics.bubbleGap + notch.height * 2, height: notch.height, alignment: .topLeading)
        .environment(\.isBubbleHovered, isHovered)
        .animation(.notchQuick, value: isHovered)
        .animation(activity == nil ? .bubbleMerge : .bubbleSplit, value: activity)
    }
}

private extension EnvironmentValues {
    /// The pointer is over the bubble, for the drop that draws it.
    @Entry var isBubbleHovered = false
}

/// A bubble coming out of the notch's end as a drop, or going back in.
private struct BubbleSplit: Transition {
    let notch: CGSize
    let ear: CGFloat
    let size: CGSize

    func body(content: Content, phase: TransitionPhase) -> some View {
        content.modifier(BubbleDrop(progress: phase.isIdentity ? 1 : 0, notch: notch, ear: ear, size: size))
    }
}

/// The bubble `progress` of the way out: 0 is a small drop inside the end of the notch, 1 the
/// bubble in its place beside it. Until it's there, the drop and the notch's end are blurred
/// together and cut off at half opacity, so a neck joins them that stretches and snaps as the
/// drop pulls away, as liquid does.
private struct BubbleDrop: ViewModifier, Animatable {
    var progress: CGFloat
    let notch: CGSize
    let ear: CGFloat
    let size: CGSize
    @Environment(\.isBubbleHovered) private var isHovered

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let scale = (0.5 + 0.5 * progress) * (isHovered ? 1.08 : 1)
        // Stretched tall while it's pulled out, so it comes away from the whole end of the notch
        // (its ear too) rather than from under it.
        let stretch = sin(min(max(progress, 0), 1) * .pi)
        let width = size.width * scale
        let height = min(size.height * scale * (1 + 0.45 * stretch), notch.height)
        // From just inside the notch's end out to its place beside it.
        let start = ActivityBubble.notchEnd - width / 2 - 2
        let end = ActivityBubble.notchEnd + NotchMetrics.bubbleGap + size.width / 2
        let center = CGPoint(x: start + (end - start) * progress, y: notch.height / 2)
        let rect = CGRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height)

        ZStack(alignment: .topLeading) {
            if progress < 1 {
                Canvas { context, _ in
                    // Applied last to first: the blur that melts the two together, the cut that
                    // gives them an edge again, and a slight one to smooth that edge.
                    context.addFilter(.blur(radius: 0.5))
                    context.addFilter(.alphaThreshold(min: 0.5, color: .black))
                    context.addFilter(.blur(radius: 4))
                    context.drawLayer { layer in
                        layer.fill(notchEndPath, with: .color(.black))
                        layer.fill(Capsule().path(in: rect), with: .color(.black))
                    }
                }
                .allowsHitTesting(false)
            }
            NotchShadow(shape: Capsule(), elevation: NotchMetrics.besideNotchElevation * min(max(progress, 0), 1))
                .frame(width: width, height: height)
                .position(x: center.x, y: center.y)
                .allowsHitTesting(false)
            // A light rim, so the bubble shows on a dark menu bar too. It comes on as the drop
            // pinches off, rather than ringing the neck.
            Capsule()
                .strokeBorder(.white.opacity((isHovered ? 0.55 : 0.3) * min(max(progress * 10 - 9, 0), 1)), lineWidth: 1)
                .frame(width: width, height: height)
                .position(x: center.x, y: center.y)
                .allowsHitTesting(false)
            content
                .scaleEffect(scale)
                .opacity(min(max(progress * 2 - 1, 0), 1))
                .position(x: center.x, y: center.y)
        }
    }

    /// The notch's right end, ear included, drawn by the notch's own shape as a compact activity
    /// has it. The rest of the shape is off to the left, out of the canvas.
    private var notchEndPath: Path {
        let reach = notch.height * 2
        return NotchShape(topRadius: ear, bottomRadius: notch.height / 2)
            .path(in: CGRect(x: -reach, y: 0, width: reach + ActivityBubble.notchEnd + ear, height: notch.height))
    }
}
