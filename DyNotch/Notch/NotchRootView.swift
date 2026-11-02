import SwiftUI

/// Root of each notch panel: the black shape plus whatever the current presentation shows.
struct NotchRootView: View {
    let model: NotchViewModel
    /// The presentation as of the last change, to pick how the next one animates.
    @State private var previous = NotchPresentation.closed

    var body: some View {
        let presentation = model.presentation
        let size = model.shapeSize(for: presentation)
        let top = model.topRadius(for: presentation)
        let bottom = model.bottomRadius(for: presentation)
        let shape = NotchShape(topRadius: top, bottomRadius: bottom)
        let hasRim = model.hasRim(presentation)
        let hidden = presentation == .closed && model.geometry.hasHardwareNotch

        ZStack(alignment: .top) {
            shape.fill(.black)

            NotchContentView(model: model, presentation: presentation)
                .frame(width: size.width, height: size.height, alignment: .top)
                .id(presentation.contentID)
                .transition(contentTransition(presentation, size: size))
                // A view on its way out loses its place in the stack and drops behind the black
                // fill. Things beside the notch keep theirs, so the art and bars fold into it rather
                // than vanish, which over a full-screen video (black beside the notch, so the
                // shape's own fold can't be seen) left nothing moving at all.
                .zIndex(presentation.isBesideNotch ? 1 : 0)

            // A light edge while an activity shows, like the Dynamic Island's, so it stands out
            // on a dark menu bar. Straight up the body's sides to the screen's edge, inside the
            // ears, which a dark menu bar hides anyway. Stroked on the body's edge and clipped to
            // it, which cuts off the stroke's outer half.
            NotchShape(topRadius: 0, bottomRadius: bottom, isOpenAtTop: true)
                .stroke(presentation.rimColor.opacity(hasRim ? presentation.rimOpacity : 0), lineWidth: 1.5)
                .clipShape(NotchShape(topRadius: 0, bottomRadius: bottom))
                .frame(width: size.width, height: size.height)
                .allowsHitTesting(false)
                .zIndex(2)
        }
        .frame(width: size.width + top * 2, height: size.height)
        .clipShape(shape)
        // Showing a notification, a click opens the notch too, wherever its own buttons don't
        // take it.
        .gesture(
            TapGesture().onEnded { model.open(haptic: false) },
            including: model.opensOnClick(presentation) ? .all : .subviews
        )
        .background {
            NotchShadow(shape: shape, elevation: presentation.elevation)
        }
        .background(alignment: .topTrailing) {
            // Under the notch, which hides it as it comes out of the notch's right end and goes
            // back in.
            ActivityBubble(
                activity: model.bubble(for: presentation),
                notch: model.besideNotch(for: presentation),
                ear: top,
                isHovered: model.isHoveringBubble,
                hasRim: model.services.settings.activityRim
            ) {
                model.openOnBubble(haptic: false)
            }
            .alignmentGuide(.trailing) { _ in ActivityBubble.notchEnd + top }
        }
        .overlay {
            if !presentation.isInteractiveContent {
                // Closed, peeking or compact: a click anywhere opens the notch.
                shape.fill(.clear)
                    .contentShape(shape)
                    .onTapGesture { model.open(haptic: false) }
            }
        }
        .opacity(hidden ? 0 : 1)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
        .animation(animation(from: previous, to: presentation), value: presentation)
        // The open notch changes size with its tab too (the Camera tab's large picture).
        .animation(.notch, value: presentation == .open ? size : nil)
        .onChange(of: presentation) { previous = presentation }
        .environment(\.colorScheme, .dark)
        .environment(\.controlActiveState, .key)
    }

    /// Activities beside the notch arriving or folding away (music starting, the player leaving
    /// after it stopped) glide in step with their content; everything else springs.
    private func animation(from old: NotchPresentation, to new: NotchPresentation) -> Animation {
        old.isBesideNotch && new.isBesideNotch && old.contentID != new.contentID ? .notchFold : .notch
    }

    /// Things beside the notch fold into it as the shape closes in, and unfold out of it,
    /// like the Dynamic Island taking an activity in; everything else blurs over in place.
    private func contentTransition(_ presentation: NotchPresentation, size: CGSize) -> AnyTransition {
        guard case .compact = presentation else {
            return AnyTransition(BlurReplaceTransition(configuration: .downUp).combined(with: ScaleTransition(0.96, anchor: .top)))
        }
        return AnyTransition(NotchFoldTransition(scale: model.geometry.notchSize.width / size.width))
    }
}

/// Scales the wings toward the middle by `scale` (the notch's width over theirs), so the
/// art and bars travel in with the closing edges and blur out as they reach the cut-out.
private struct NotchFoldTransition: Transition {
    let scale: CGFloat

    func body(content: Content, phase: TransitionPhase) -> some View {
        content
            .scaleEffect(phase.isIdentity ? 1 : scale, anchor: .center)
            .blur(radius: phase.isIdentity ? 0 : 4)
            .opacity(phase.isIdentity ? 1 : 0)
    }
}

private extension NotchPresentation {
    /// Closed, or showing something in the wings beside the cut-out.
    var isBesideNotch: Bool {
        switch self {
        case .closed, .compact: true
        default: false
        }
    }

    /// Presentations whose content has its own buttons.
    var isInteractiveContent: Bool {
        switch self {
        case .open, .call, .dropTarget, .transient: true
        default: false
        }
    }

    /// How bright the rim is: on while an activity shows beside the notch or drops from it,
    /// brighter under the pointer as the bubble's.
    var rimOpacity: CGFloat {
        switch self {
        case .compact(_, let hovering), .transient(_, let hovering):
            hovering ? NotchMetrics.hoveredRimOpacity : NotchMetrics.rimOpacity
        default: 0
        }
    }

    /// A call's rim is green, as the Dynamic Island's; any other activity's white.
    var rimColor: Color {
        if case .compact(.call, _) = self { return CallStyle.green }
        return .white
    }

    /// How far the notch stands off the screen, for its shadow: not at all while it's just the
    /// cut-out, a little when it grows beside it, fully once it drops down.
    var elevation: CGFloat {
        if isExpanded { return 1 }
        return self == .closed ? 0 : NotchMetrics.besideNotchElevation
    }
}

/// Lifts the notch off what's under it: a tight shadow along its edge and a soft, wide one
/// further down, both deeper the higher it stands. Cast by the shape alone, so nothing
/// redrawing inside it redraws them.
struct NotchShadow<S: Shape>: View {
    let shape: S
    let elevation: CGFloat

    var body: some View {
        ZStack {
            shape.fill(.black)
                .shadow(color: .black.opacity(0.45 * elevation), radius: 20 * elevation, y: 14 * elevation)
            shape.fill(.black)
                .shadow(color: .black.opacity(0.3 * elevation), radius: 1 + 3 * elevation, y: 1 + elevation)
        }
    }
}

private struct NotchContentView: View {
    let model: NotchViewModel
    let presentation: NotchPresentation

    var body: some View {
        switch presentation {
        case .closed, .peek:
            Color.clear
        case .compact(let activity, let hovering):
            CompactActivityView(activity: activity, notch: model.besideNotch(for: presentation), isHovering: hovering)
        case .transient(let activity, let hovering):
            // The band beside the notch grows with the shape while hovered, as a compact
            // activity's, so its content stays centred in it. One that drops down lays out under
            // the cut-out itself.
            let notch = presentation.isExpanded ? model.geometry.notchSize : model.besideNotch(for: presentation)
            let band = CGSize(width: notch.width, height: notch.height + (hovering ? NotchMetrics.hoverGrowth.height : 0))
            LiveActivityView(activity: activity, notch: band)
        case .open:
            OpenNotchView(model: model)
        case .call:
            CallControlsView(notch: model.geometry.notchSize)
        case .dropTarget:
            DropTargetView(model: model)
        }
    }
}

/// Lays out content in the two "wings" left and right of the notch cut-out.
struct WingsLayout<Leading: View, Trailing: View>: View {
    let notch: CGSize
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 0) {
            leading
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Color.clear.frame(width: notch.width)
            trailing
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: notch.height)
    }
}
