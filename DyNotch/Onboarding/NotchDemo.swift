import QuartzCore
import SwiftUI

/// A small notch on a strip of desktop, acting out what a step of the tour teaches, over and over.
/// With Reduce Motion it holds still at the moment that shows it best.
struct NotchDemo: View {
    @Environment(AppServices.self) private var services
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale
    let step: OnboardingStep

    var body: some View {
        let settings = services.settings
        let kind: DemoKind = switch step {
        case .open: .open(clicks: settings.openMode == .click)
        case .tabs: .tabs(fingers: settings.tabSwipe == .off ? 0 : settings.tabSwipe == .twoFingers ? 2 : 3)
        case .shelf: .shelf
        default: .hud
        }
        DemoLayers(kind: kind, isStill: reduceMotion, scale: displayScale)
            .frame(width: Demo.card.width, height: Demo.card.height)
            .background {
                RoundedRectangle(cornerRadius: Demo.cornerRadius)
                    .fill(.black)
                    .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
            }
            .accessibilityHidden(true)
    }
}

enum DemoKind: Equatable {
    case open(clicks: Bool)
    /// With no fingers the tabs are clicked: swiping is off.
    case tabs(fingers: Int)
    case shelf
    case hud
}

/// The real notch's measures, at half size.
private enum Demo {
    static let card = CGSize(width: 440, height: 200)
    static let cornerRadius: CGFloat = 18
    static let closed = CGSize(width: 93, height: 16)
    static let open = CGSize(width: NotchMetrics.openWidth / 2, height: closed.height + NotchMetrics.openContentHeight / 2)
    static let dropTarget = CGSize(width: NotchMetrics.dropTargetWidth / 2, height: closed.height + NotchMetrics.dropTargetContentHeight / 2)
    static let hud = CGSize(width: 165, height: closed.height + 15)
    /// The open notch's tabs, below the strip beside the cut-out.
    static let page = CGSize(width: open.width - 16, height: open.height - closed.height - 12)
    static let pageSpacing: CGFloat = 16
}

/// A notch shape: its size and corner radii.
private struct NotchForm {
    var size: CGSize
    var top: CGFloat
    var bottom: CGFloat

    static let closed = NotchForm(size: Demo.closed, top: 2, bottom: 5)
    static let open = NotchForm(size: Demo.open, top: 7, bottom: 16)
    static let dropTarget = NotchForm(size: Demo.dropTarget, top: 7, bottom: 14)
    static let hud = NotchForm(size: Demo.hud, top: 5, bottom: 12)

    /// The way from closed to `form`, `progress` along (a spring takes it a little past 1).
    static func closed(to form: NotchForm, _ progress: CGFloat) -> NotchForm {
        func mix(_ a: CGFloat, _ b: CGFloat) -> CGFloat { max(0, a + (b - a) * progress) }
        return NotchForm(
            size: CGSize(width: mix(closed.size.width, form.size.width), height: mix(closed.size.height, form.size.height)),
            top: mix(closed.top, form.top),
            bottom: mix(closed.bottom, form.bottom)
        )
    }

    /// Hanging from the top of the card, in the middle.
    var path: CGPath {
        let rect = CGRect(x: Demo.card.width / 2 - size.width / 2 - top, y: 0, width: size.width + top * 2, height: size.height)
        return NotchShape(topRadius: top, bottomRadius: bottom).path(in: rect).cgPath
    }
}

/// How much of what's inside a growing notch shows: none until it's halfway open.
private func contentOpacity(_ progress: CGFloat) -> Double {
    Double(min(1, max(0, (progress - 0.5) * 2)))
}

/// From the card's top center, where the notch hangs, to its own coordinates.
private func inCard(_ point: CGPoint) -> CGPoint {
    CGPoint(x: Demo.card.width / 2 + point.x, y: point.y)
}

/// A timeline's values 60 times a second, from start to end.
private func frames<Value>(_ timeline: KeyframeTimeline<Value>) -> [Value] {
    let count = Int(timeline.duration * 60) + 1
    return (0..<count).map { timeline.value(time: timeline.duration * Double($0) / Double(count - 1)) }
}

// MARK: - Layers

private struct DemoLayers: NSViewRepresentable {
    let kind: DemoKind
    let isStill: Bool
    let scale: CGFloat

    func makeNSView(context: Context) -> DemoLayerView { DemoLayerView() }

    func updateNSView(_ view: DemoLayerView, context: Context) {
        view.show(kind, isStill: isStill, scale: scale)
    }
}

/// Plays a demo with Core Animation, out of process: SwiftUI draws each part once, and the
/// timelines below are played as keyframe animations. Drawn by SwiftUI frame by frame, the same
/// demos took 20–50% CPU.
private final class DemoLayerView: NSView {
    private var shown: (kind: DemoKind, isStill: Bool, scale: CGFloat)?
    /// Measures from the top left, as SwiftUI does. (Flipping the view's own layer doesn't hold.)
    private let stage = CALayer()

    init() {
        super.init(frame: NSRect(origin: .zero, size: Demo.card))
        layer = CALayer()
        wantsLayer = true
        stage.frame = bounds
        stage.isGeometryFlipped = true
        layer?.addSublayer(stage)
    }

    required init?(coder: NSCoder) { fatalError() }

    func show(_ kind: DemoKind, isStill: Bool, scale: CGFloat) {
        if let shown, shown.kind == kind, shown.isStill == isStill, shown.scale == scale { return }
        shown = (kind, isStill, scale)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        stage.sublayers = nil
        let stage = DemoStage(root: stage, scale: scale)
        switch kind {
        case .open(let clicks): stage.playOpen(clicks: clicks, isStill: isStill)
        case .tabs(let fingers): stage.playTabs(fingers: fingers, isStill: isStill)
        case .shelf: stage.playShelf(isStill: isStill)
        case .hud: stage.playHUD(isStill: isStill)
        }
        CATransaction.commit()
    }
}

/// Builds a demo's layers in `root`, the card.
private struct DemoStage {
    let root: CALayer
    let scale: CGFloat

    init(root: CALayer, scale: CGFloat) {
        self.root = root
        self.scale = scale
        root.contents = render(DemoDesktop().frame(width: Demo.card.width, height: Demo.card.height))
        root.contentsScale = scale
        root.cornerRadius = Demo.cornerRadius
        root.masksToBounds = true
        root.borderWidth = 1
        root.borderColor = CGColor(gray: 1, alpha: 0.12)
    }

    private var bounds: CGRect { CGRect(origin: .zero, size: Demo.card) }

    // MARK: Opening

    func playOpen(clicks: Bool, isStill: Bool) {
        let timeline = OpenScene.timeline(clicks: clicks)
        let scenes = isStill ? [OpenScene.still] : frames(timeline)
        let duration = timeline.duration
        let inside = notch(scenes.map { .closed(to: .open, $0.open) }, elevation: scenes.map(\.open), duration: duration)
        let content = hanging(image(MiniOpenNotch(selection: 0)))
        play(content, "opacity", scenes.map { contentOpacity($0.open) }, duration: duration)
        inside.addSublayer(content)
        if clicks {
            let ring = CAShapeLayer()
            ring.frame = bounds
            ring.fillColor = nil
            ring.strokeColor = .white
            ring.lineWidth = 1.5
            play(ring, "path", scenes.map { scene in
                let tip = inCard(scene.pointer), size = 6 + scene.click * 22
                return CGPath(ellipseIn: CGRect(x: tip.x - size / 2, y: tip.y - size / 2, width: size, height: size), transform: nil)
            }, duration: duration)
            play(ring, "opacity", scenes.map { $0.click > 0 ? 1 - $0.click : 0 }, duration: duration)
            root.addSublayer(ring)
        }
        pointer(scenes.map { inCard($0.pointer) }, duration: duration)
    }

    // MARK: Tabs

    func playTabs(fingers: Int, isStill: Bool) {
        let timeline = TabsScene.timeline
        let scenes = isStill ? [TabsScene.still] : frames(timeline)
        let duration = timeline.duration
        let inside = notch([.open], elevation: [1], duration: duration)
        inside.addSublayer(hanging(image(MiniOpenNotch(selection: nil, showsPages: false))))

        // The selected tab's capsule, and its icon lit up inside it.
        let bar = CGPoint(x: Demo.card.width / 2 + MiniTabIcons.leading, y: (Demo.closed.height - MiniTabIcons.icon.height) / 2)
        let stride = MiniTabIcons.icon.width + MiniTabIcons.spacing
        let tabs = scenes.map(\.tab)
        let capsule = CALayer()
        capsule.backgroundColor = CGColor(gray: 1, alpha: 0.2)
        capsule.bounds = CGRect(origin: .zero, size: MiniTabIcons.icon)
        capsule.cornerRadius = MiniTabIcons.icon.height / 2
        capsule.anchorPoint = .zero
        play(capsule, "position", tabs.map { NSValue(point: CGPoint(x: bar.x + $0 * stride, y: bar.y)) }, duration: duration)
        let lit = image(MiniTabIcons(selection: nil, isLit: true))
        lit.anchorPoint = .zero
        lit.position = bar
        let litMask = CALayer()
        litMask.backgroundColor = .black
        litMask.bounds = capsule.bounds
        litMask.cornerRadius = capsule.cornerRadius
        litMask.anchorPoint = .zero
        play(litMask, "position", tabs.map { NSValue(point: CGPoint(x: $0 * stride, y: 0)) }, duration: duration)
        lit.mask = litMask
        inside.addSublayer(capsule)
        inside.addSublayer(lit)

        // The tabs side by side, slid along to the one showing.
        let window = CALayer()
        window.frame = CGRect(
            x: (Demo.card.width - Demo.page.width) / 2, y: Demo.closed.height + 5, width: Demo.page.width, height: Demo.page.height
        )
        window.masksToBounds = true
        let pages = image(MiniPages())
        pages.anchorPoint = .zero
        play(pages, "position", tabs.map { NSValue(point: CGPoint(x: -$0 * (Demo.page.width + Demo.pageSpacing), y: 0)) }, duration: duration)
        window.addSublayer(pages)
        inside.addSublayer(window)

        if fingers > 0 {
            let hand = image(FingerTips(count: fingers))
            play(hand, "position", scenes.map { NSValue(point: inCard(CGPoint(x: $0.fingers, y: 78))) }, duration: duration)
            play(hand, "opacity", scenes.map(\.touch), duration: duration)
            root.addSublayer(hand)
        } else {
            pointer(scenes.map { inCard(CGPoint(x: MiniTabIcons.center(of: $0.pointer), y: 9)) }, duration: duration)
        }
    }

    // MARK: Shelf

    func playShelf(isStill: Bool) {
        let timeline = ShelfScene.timeline
        let scenes = isStill ? [ShelfScene.still] : frames(timeline)
        let duration = timeline.duration
        let inside = notch(scenes.map { .closed(to: .dropTarget, $0.open) }, elevation: scenes.map(\.open), duration: duration)
        let tiles = hanging(image(MiniDropTarget(isShelfLit: false)))
        let litTiles = hanging(image(MiniDropTarget(isShelfLit: true)))
        play(tiles, "opacity", scenes.map { contentOpacity($0.open) }, duration: duration)
        play(litTiles, "opacity", scenes.map { contentOpacity($0.open) * $0.over }, duration: duration)
        inside.addSublayer(tiles)
        inside.addSublayer(litTiles)

        let file = image(DocumentGlyph())
        play(file, "position", scenes.map { NSValue(point: inCard($0.file)) }, duration: duration)
        play(file, "transform", scenes.map { NSValue(caTransform3D: CATransform3DMakeScale($0.fileScale, $0.fileScale, 1)) }, duration: duration)
        play(file, "opacity", scenes.map { $0.fileOpacity * 0.9 }, duration: duration)
        root.addSublayer(file)
        pointer(
            scenes.map { inCard(CGPoint(x: $0.file.x + 6, y: $0.file.y + 4)) },
            opacity: scenes.map(\.fileOpacity), duration: duration
        )
    }

    // MARK: Volume

    func playHUD(isStill: Bool) {
        let timeline = HUDScene.timeline
        let scenes = isStill ? [HUDScene.still] : frames(timeline)
        let duration = timeline.duration
        let inside = notch(scenes.map { .closed(to: .hud, $0.open) }, elevation: scenes.map(\.open), duration: duration)
        let content = CALayer()
        content.frame = bounds
        play(content, "opacity", scenes.map { contentOpacity($0.open) }, duration: duration)
        inside.addSublayer(content)
        content.addSublayer(hanging(image(MiniHUD())))

        let barWidth = MiniHUD.barWidth
        let fill = CALayer()
        fill.backgroundColor = .white
        fill.cornerRadius = 2
        fill.anchorPoint = .zero
        fill.position = CGPoint(x: (Demo.card.width - barWidth) / 2, y: Demo.closed.height + (Demo.hud.height - Demo.closed.height - 4) / 2)
        let widths = scenes.map { max(4, barWidth * $0.level) }
        fill.bounds = CGRect(x: 0, y: 0, width: widths[0], height: 4)
        play(fill, "bounds.size.width", widths, duration: duration, setsModel: false)
        content.addSublayer(fill)

        // The percentage, a picture for each number it goes through.
        let numbers = scenes.map { Int(($0.level * 100).rounded()) }
        var pictures: [Int: CGImage] = [:]
        for number in Set(numbers) {
            pictures[number] = render(
                Text("\(number)")
                    .font(.system(size: 7.5, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.85))
            )
        }
        let label = CALayer()
        label.contentsScale = scale
        label.contentsGravity = .right
        if let widest = pictures.values.max(by: { $0.width < $1.width }) {
            label.bounds = CGRect(x: 0, y: 0, width: CGFloat(widest.width) / scale, height: CGFloat(widest.height) / scale)
        }
        label.anchorPoint = CGPoint(x: 1, y: 0.5)
        label.position = CGPoint(x: Demo.card.width / 2 + Demo.hud.width / 2 - 6, y: Demo.closed.height / 2)
        play(label, "contents", numbers.compactMap { pictures[$0] }, duration: duration, isDiscrete: true)
        content.addSublayer(label)

        // The volume keys, the up one pressed.
        let down = image(DemoKey(symbol: "speaker.wave.1.fill"))
        let up = image(DemoKey(symbol: "speaker.wave.3.fill"))
        down.position = CGPoint(x: Demo.card.width / 2 - 26, y: 152)
        up.position = CGPoint(x: Demo.card.width / 2 + 26, y: 152)
        play(up, "transform", scenes.map { NSValue(caTransform3D: CATransform3DMakeScale(1 - 0.07 * $0.press, 1 - 0.07 * $0.press, 1)) }, duration: duration)
        let pressed = CALayer()
        pressed.backgroundColor = .black
        pressed.cornerRadius = 6
        pressed.frame = up.bounds.insetBy(dx: DemoKey.margin, dy: DemoKey.margin)
        play(pressed, "opacity", scenes.map { 0.3 * $0.press }, duration: duration)
        up.addSublayer(pressed)
        root.addSublayer(down)
        root.addSublayer(up)
    }

    // MARK: Parts

    /// The black notch, shaped by `forms` frame by frame, with its shadow coming as it opens.
    /// Returns a layer clipped to it, for what's inside.
    private func notch(_ forms: [NotchForm], elevation: [CGFloat], duration: TimeInterval) -> CALayer {
        let paths = forms.map(\.path)
        let shape = CAShapeLayer()
        shape.frame = bounds
        shape.fillColor = .black
        shape.shadowColor = .black
        shape.shadowRadius = 5
        shape.shadowOffset = CGSize(width: 0, height: 3)
        play(shape, "path", paths, duration: duration)
        play(shape, "shadowPath", paths, duration: duration)
        play(shape, "shadowOpacity", elevation.map { 0.45 * min(1, max(0, $0)) }, duration: duration)
        root.addSublayer(shape)

        let inside = CALayer()
        inside.frame = bounds
        let mask = CAShapeLayer()
        mask.frame = bounds
        play(mask, "path", paths, duration: duration)
        inside.mask = mask
        root.addSublayer(inside)
        return inside
    }

    /// The pointer, its tip at `tips` frame by frame.
    private func pointer(_ tips: [CGPoint], opacity: [Double]? = nil, duration: TimeInterval) {
        let arrow = image(PointerGlyph())
        arrow.anchorPoint = .zero
        play(arrow, "position", tips.map { NSValue(point: CGPoint(x: $0.x - PointerGlyph.tip, y: $0.y - PointerGlyph.tip)) }, duration: duration)
        if let opacity { play(arrow, "opacity", opacity, duration: duration) }
        root.addSublayer(arrow)
    }

    /// `layer` at the top of the card, in the middle, where the notch's content goes.
    private func hanging(_ layer: CALayer) -> CALayer {
        layer.anchorPoint = CGPoint(x: 0.5, y: 0)
        layer.position = CGPoint(x: Demo.card.width / 2, y: 0)
        return layer
    }

    /// A layer showing `view`, as big as it is.
    private func image(_ view: some View) -> CALayer {
        let layer = CALayer()
        layer.contentsScale = scale
        if let picture = render(view) {
            layer.contents = picture
            layer.bounds = CGRect(x: 0, y: 0, width: CGFloat(picture.width) / scale, height: CGFloat(picture.height) / scale)
        }
        return layer
    }

    private func render(_ view: some View) -> CGImage? {
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, .dark))
        renderer.scale = scale
        return renderer.cgImage
    }

    /// Sets `keyPath` to the first of `values`, and with more than one plays them evenly over
    /// `duration`, over and over. Starting together, all of a demo's animations stay in step.
    private func play(
        _ layer: CALayer, _ keyPath: String, _ values: [Any], duration: TimeInterval,
        isDiscrete: Bool = false, setsModel: Bool = true
    ) {
        guard let first = values.first else { return }
        if setsModel { layer.setValue(first, forKeyPath: keyPath) }
        guard values.count > 1 else { return }
        let animation = CAKeyframeAnimation(keyPath: keyPath)
        animation.values = values
        animation.duration = duration
        animation.calculationMode = isDiscrete ? .discrete : .linear
        animation.repeatCount = .infinity
        layer.add(animation, forKey: keyPath)
    }
}

/// A wallpaper with a menu bar, which the notch sits in the middle of.
private struct DemoDesktop: View {
    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(
                colors: [Color(red: 0.12, green: 0.15, blue: 0.38), Color(red: 0.4, green: 0.22, blue: 0.5), Color(red: 0.86, green: 0.47, blue: 0.42)],
                startPoint: .top, endPoint: .bottom
            )
            HStack(spacing: 8) {
                Image(systemName: "apple.logo")
                    .font(.system(size: 8))
                ForEach([20, 12, 12, 14], id: \.self) { width in
                    Capsule().frame(width: CGFloat(width), height: 3)
                }
                Spacer()
                Image(systemName: "wifi")
                Image(systemName: "battery.75percent")
                Text("9:41")
            }
            .font(.system(size: 7, weight: .semibold))
            .foregroundStyle(.white.opacity(0.75))
            .padding(.horizontal, 12)
            .frame(height: Demo.closed.height)
            .background(.black.opacity(0.15))
        }
    }
}

/// The macOS arrow, with room around it for its shadow.
private struct PointerGlyph: View {
    /// How far in from the picture's corner the arrow's tip is.
    static let tip: CGFloat = 6

    var body: some View {
        Image(systemName: "cursorarrow")
            .font(.system(size: 17))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.6), radius: 1.5, y: 1)
            .frame(width: 18, height: 18, alignment: .topLeading)
            .padding(4)
    }
}

private struct FingerTips: View {
    let count: Int

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            ForEach(0..<count, id: \.self) { finger in
                Circle()
                    .fill(.white.opacity(0.9))
                    .frame(width: 10, height: 10)
                    .shadow(color: .black.opacity(0.4), radius: 3)
                    // The middle finger reaches a little further.
                    .offset(y: count == 3 && finger == 1 ? -3 : 0)
            }
        }
        .padding(8)
    }
}

private struct DocumentGlyph: View {
    var body: some View {
        Image(systemName: "doc.richtext.fill")
            .font(.system(size: 24))
            .foregroundStyle(.white, .blue)
            .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
            .padding(8)
    }
}

// MARK: - Opening

nonisolated private struct OpenScene {
    var open: CGFloat = 0
    /// Where the pointer's tip is, from the top center.
    var pointer = CGPoint(x: 120, y: 168)
    /// A click spreading out from the pointer, 0 to 1.
    var click: CGFloat = 0

    static let still = OpenScene(open: 1, pointer: CGPoint(x: 40, y: 70))

    /// The pointer goes up to the notch, which opens (on its own, or when clicked), and closes
    /// once the pointer leaves.
    static func timeline(clicks: Bool) -> KeyframeTimeline<OpenScene> {
        let start = CGPoint(x: 120, y: 168)
        return KeyframeTimeline(initialValue: OpenScene()) {
            KeyframeTrack(\.pointer) {
                LinearKeyframe(start, duration: 0.4)
                CubicKeyframe(CGPoint(x: 2, y: 7), duration: 0.9)
                LinearKeyframe(CGPoint(x: 2, y: 7), duration: 0.6)
                CubicKeyframe(CGPoint(x: 40, y: 70), duration: 0.6)
                LinearKeyframe(CGPoint(x: 40, y: 70), duration: 0.6)
                CubicKeyframe(start, duration: 0.8)
                LinearKeyframe(start, duration: 0.5)
            }
            KeyframeTrack(\.open) {
                LinearKeyframe(0, duration: 1.45)
                SpringKeyframe(1, duration: 2.1, spring: Spring(duration: 0.45, bounce: 0.25))
                SpringKeyframe(0, duration: 0.85, spring: Spring(duration: 0.4, bounce: 0.1))
            }
            KeyframeTrack(\.click) {
                LinearKeyframe(0, duration: 1.4)
                CubicKeyframe(clicks ? 1 : 0, duration: 0.4)
                MoveKeyframe(0)
                LinearKeyframe(0, duration: 2.6)
            }
        }
    }
}

// MARK: - Tabs

nonisolated private struct TabsScene {
    /// The tab showing, 0 for Home; in between while it slides.
    var tab: CGFloat = 0
    /// How far the fingers are across the notch.
    var fingers: CGFloat = 36
    var touch: Double = 0
    /// The tab the pointer is over, when the tabs are clicked rather than swiped.
    var pointer: CGFloat = 0

    static let still = TabsScene(tab: 1, fingers: -10, touch: 1, pointer: 1)

    /// Fingers swipe across the open notch, which slides to the next tab and back; without
    /// swiping, the pointer clicks the tabs instead. Two swipes to the left, to the next tabs,
    /// then two back.
    static var timeline: KeyframeTimeline<TabsScene> {
        let swipe = Spring(duration: 0.45, bounce: 0.15)
        return KeyframeTimeline(initialValue: TabsScene()) {
            KeyframeTrack(\.tab) {
                LinearKeyframe(0, duration: 0.45)
                SpringKeyframe(1, duration: 1.5, spring: swipe)
                SpringKeyframe(2, duration: 1.5, spring: swipe)
                SpringKeyframe(1, duration: 1.5, spring: swipe)
                SpringKeyframe(0, duration: 1.05, spring: swipe)
            }
            KeyframeTrack(\.fingers) {
                MoveKeyframe(36)
                CubicKeyframe(-36, duration: 0.5)
                LinearKeyframe(-36, duration: 1)
                MoveKeyframe(36)
                CubicKeyframe(-36, duration: 0.5)
                LinearKeyframe(-36, duration: 1)
                MoveKeyframe(-36)
                CubicKeyframe(36, duration: 0.5)
                LinearKeyframe(36, duration: 1)
                MoveKeyframe(-36)
                CubicKeyframe(36, duration: 0.5)
                LinearKeyframe(36, duration: 1)
            }
            KeyframeTrack(\.touch) {
                CubicKeyframe(1, duration: 0.12)
                LinearKeyframe(1, duration: 0.33)
                CubicKeyframe(0, duration: 0.15)
                LinearKeyframe(0, duration: 0.9)
                CubicKeyframe(1, duration: 0.12)
                LinearKeyframe(1, duration: 0.33)
                CubicKeyframe(0, duration: 0.15)
                LinearKeyframe(0, duration: 0.9)
                CubicKeyframe(1, duration: 0.12)
                LinearKeyframe(1, duration: 0.33)
                CubicKeyframe(0, duration: 0.15)
                LinearKeyframe(0, duration: 0.9)
                CubicKeyframe(1, duration: 0.12)
                LinearKeyframe(1, duration: 0.33)
                CubicKeyframe(0, duration: 0.15)
                LinearKeyframe(0, duration: 0.9)
            }
            KeyframeTrack(\.pointer) {
                CubicKeyframe(1, duration: 0.4)
                LinearKeyframe(1, duration: 1.1)
                CubicKeyframe(2, duration: 0.4)
                LinearKeyframe(2, duration: 1.1)
                CubicKeyframe(1, duration: 0.4)
                LinearKeyframe(1, duration: 1.1)
                CubicKeyframe(0, duration: 0.4)
                LinearKeyframe(0, duration: 1.1)
            }
        }
    }
}

/// What the open notch shows: the tab bar and battery beside the cut-out, and the tab
/// `selection` below it. Without a selection, no tab is picked out.
private struct MiniOpenNotch: View {
    let selection: Int?
    var showsPages = true

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ZStack(alignment: .leading) {
                    if let selection {
                        Capsule()
                            .fill(.white.opacity(0.2))
                            .frame(width: MiniTabIcons.icon.width, height: MiniTabIcons.icon.height)
                            .offset(x: CGFloat(selection) * (MiniTabIcons.icon.width + MiniTabIcons.spacing))
                    }
                    MiniTabIcons(selection: selection)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 16)
                Color.clear.frame(width: Demo.closed.width)
                HStack(spacing: 6) {
                    Image(systemName: "battery.75percent")
                    Image(systemName: "gearshape.fill")
                }
                .font(.system(size: 7, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 16)
            }
            .frame(height: Demo.closed.height)
            if showsPages {
                MiniPages()
                    .offset(x: -CGFloat(selection ?? 0) * (Demo.page.width + Demo.pageSpacing))
                    .frame(width: Demo.page.width, height: Demo.page.height, alignment: .leading)
                    .clipped()
                    .padding(.top, 5)
            }
        }
        .frame(width: Demo.open.width + 14, height: Demo.open.height, alignment: .top)
    }
}

private struct MiniTabIcons: View {
    static let symbols = ["house.fill", "tray.full.fill", "timer", "web.camera.fill"]
    static let icon = CGSize(width: 18, height: 11)
    static let spacing: CGFloat = 2
    /// Where the icons start, from the notch's center.
    static let leading = 16 - (Demo.open.width + 14) / 2

    /// The middle of tab `index`, from the notch's center.
    static func center(of index: CGFloat) -> CGFloat {
        leading + icon.width / 2 + index * (icon.width + spacing)
    }

    let selection: Int?
    /// All of them white, as the selected one is.
    var isLit = false

    var body: some View {
        HStack(spacing: Self.spacing) {
            ForEach(Array(Self.symbols.enumerated()), id: \.offset) { index, symbol in
                Image(systemName: symbol)
                    .font(.system(size: 6.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(isLit || index == selection ? 1 : 0.5))
                    .frame(width: Self.icon.width, height: Self.icon.height)
            }
        }
    }
}

/// The tabs, side by side.
private struct MiniPages: View {
    var body: some View {
        HStack(spacing: Demo.pageSpacing) {
            MiniHome()
            MiniShelf()
            MiniTimers()
            MiniCamera()
        }
        .fixedSize()
    }
}

/// A card of the open notch, in its widget's color.
private struct MiniCard<Content: View>: View {
    var tint: Color?
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(7)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background((tint ?? .white).opacity(tint == nil ? 0.1 : 0.2), in: .rect(cornerRadius: 10))
            .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.1), lineWidth: 0.5) }
    }
}

private struct MiniHome: View {
    var body: some View {
        HStack(spacing: 5) {
            MiniCard(tint: .pink) {
                VStack(alignment: .leading, spacing: 5) {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(LinearGradient(colors: [.pink, .orange], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 32, height: 32)
                    Capsule().fill(.white.opacity(0.85)).frame(width: 54, height: 4)
                    Capsule().fill(.white.opacity(0.4)).frame(width: 38, height: 4)
                    HStack(spacing: 10) {
                        Image(systemName: "backward.fill")
                        Image(systemName: "pause.fill")
                        Image(systemName: "forward.fill")
                    }
                    .font(.system(size: 7))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.top, 2)
                }
            }
            MiniCard(tint: .purple) {
                VStack(spacing: 2) {
                    Text("9:41")
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                    Text("Tuesday 13")
                        .font(.system(size: 7, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            MiniCard(tint: .red) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("OCTOBER")
                        .font(.system(size: 6, weight: .bold))
                        .foregroundStyle(.red)
                    Grid(horizontalSpacing: 5, verticalSpacing: 5) {
                        ForEach(0..<5, id: \.self) { row in
                            GridRow {
                                ForEach(0..<7, id: \.self) { column in
                                    let isToday = row == 1 && column == 4
                                    Circle()
                                        .fill(isToday ? AnyShapeStyle(.red) : AnyShapeStyle(.white.opacity(0.35)))
                                        .frame(width: isToday ? 6 : 3, height: isToday ? 6 : 3)
                                        .frame(width: 6, height: 6)
                                }
                            }
                        }
                    }
                }
            }
        }
        .foregroundStyle(.white)
        .frame(width: Demo.page.width, height: Demo.page.height)
    }
}

private struct MiniShelf: View {
    private static let files: [(String, Color)] = [
        ("doc.richtext.fill", .blue), ("photo.fill", .green), ("film.fill", .purple), ("folder.fill", .cyan),
    ]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Self.files, id: \.0) { symbol, tint in
                VStack(spacing: 6) {
                    Image(systemName: symbol)
                        .font(.system(size: 22))
                        .foregroundStyle(tint.gradient)
                    Capsule().fill(.white.opacity(0.5)).frame(width: 34, height: 3)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.white.opacity(0.07), in: .rect(cornerRadius: 10))
            }
        }
        .frame(width: Demo.page.width, height: Demo.page.height)
    }
}

private struct MiniTimers: View {
    var body: some View {
        MiniCard(tint: .orange) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().stroke(.white.opacity(0.15), lineWidth: 4)
                    Circle()
                        .trim(from: 0, to: 0.72)
                        .stroke(.orange, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 58, height: 58)
                VStack(alignment: .leading, spacing: 6) {
                    Text("03:36")
                        .font(.system(size: 24, weight: .semibold, design: .rounded).monospacedDigit())
                    HStack(spacing: 4) {
                        ForEach(["1m", "5m", "10m"], id: \.self) { preset in
                            Text(preset)
                                .font(.system(size: 7, weight: .semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.white.opacity(0.15), in: .capsule)
                        }
                    }
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: Demo.page.width, height: Demo.page.height)
    }
}

private struct MiniCamera: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(LinearGradient(colors: [Color(white: 0.32), Color(white: 0.18)], startPoint: .top, endPoint: .bottom))
            .overlay {
                Image(systemName: "person.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.white.opacity(0.45))
                    .offset(y: 8)
            }
            .clipShape(.rect(cornerRadius: 10))
            .frame(width: 150, height: Demo.page.height)
            .frame(width: Demo.page.width, height: Demo.page.height)
    }
}

// MARK: - Shelf

nonisolated private struct ShelfScene {
    /// Where the dragged file is, from the top center.
    var file = CGPoint(x: -150, y: 160)
    var fileOpacity: Double = 0
    var fileScale: CGFloat = 1
    var open: CGFloat = 0
    /// The file is over the Shelf tile, which lights up.
    var over: Double = 0

    static let still = ShelfScene(file: CGPoint(x: -52, y: 46), fileOpacity: 1, open: 1, over: 1)

    /// A file dragged up to the notch, which opens into Shelf and AirDrop; it's dropped on Shelf.
    static var timeline: KeyframeTimeline<ShelfScene> {
        let start = CGPoint(x: -150, y: 160)
        return KeyframeTimeline(initialValue: ShelfScene()) {
            KeyframeTrack(\.file) {
                LinearKeyframe(start, duration: 0.3)
                CubicKeyframe(CGPoint(x: -75, y: 70), duration: 0.9)
                CubicKeyframe(CGPoint(x: -52, y: 46), duration: 0.45)
                LinearKeyframe(CGPoint(x: -52, y: 46), duration: 2.35)
            }
            KeyframeTrack(\.fileOpacity) {
                CubicKeyframe(1, duration: 0.3)
                LinearKeyframe(1, duration: 1.7)
                CubicKeyframe(0, duration: 0.3)
                LinearKeyframe(0, duration: 1.7)
            }
            KeyframeTrack(\.fileScale) {
                LinearKeyframe(1, duration: 2)
                CubicKeyframe(0.3, duration: 0.3)
                LinearKeyframe(0.3, duration: 1.7)
            }
            KeyframeTrack(\.open) {
                LinearKeyframe(0, duration: 0.9)
                SpringKeyframe(1, duration: 1.7, spring: Spring(duration: 0.45, bounce: 0.25))
                SpringKeyframe(0, duration: 1.4, spring: Spring(duration: 0.4, bounce: 0.1))
            }
            KeyframeTrack(\.over) {
                LinearKeyframe(0, duration: 1.45)
                CubicKeyframe(1, duration: 0.2)
                LinearKeyframe(1, duration: 0.55)
                CubicKeyframe(0, duration: 0.3)
                LinearKeyframe(0, duration: 1.5)
            }
        }
    }
}

private struct MiniDropTarget: View {
    let isShelfLit: Bool

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: Demo.closed.height)
            HStack(spacing: 5) {
                tile("Shelf", "tray.and.arrow.down.fill", isLit: isShelfLit)
                tile("AirDrop", "dot.radiowaves.up.forward", isLit: false)
            }
            .padding(.horizontal, 7)
            .padding(.top, 4)
            .padding(.bottom, 6)
        }
        .frame(width: Demo.dropTarget.width + 14, height: Demo.dropTarget.height)
    }

    private func tile(_ title: LocalizedStringKey, _ symbol: String, isLit: Bool) -> some View {
        VStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
            Text(title)
                .font(.system(size: 6.5, weight: .semibold))
        }
        .foregroundStyle(.white.opacity(isLit ? 1 : 0.75))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.white.opacity(0.12), in: .rect(cornerRadius: 10))
        .background(Color.accentColor.opacity(isLit ? 0.6 : 0), in: .rect(cornerRadius: 10))
    }
}

// MARK: - Volume

nonisolated private struct HUDScene {
    var open: CGFloat = 0
    var level: CGFloat = 0.375
    /// The volume up key, 1 all the way down.
    var press: CGFloat = 0

    static let still = HUDScene(open: 1, level: 0.5625)

    /// The volume up key pressed three times: the notch shows the level going up, then folds away.
    static var timeline: KeyframeTimeline<HUDScene> {
        let step = Spring(duration: 0.3, bounce: 0.1)
        return KeyframeTimeline(initialValue: HUDScene()) {
            KeyframeTrack(\.press) {
                LinearKeyframe(0, duration: 0.4)
                CubicKeyframe(1, duration: 0.08)
                CubicKeyframe(0, duration: 0.14)
                LinearKeyframe(0, duration: 0.28)
                CubicKeyframe(1, duration: 0.08)
                CubicKeyframe(0, duration: 0.14)
                LinearKeyframe(0, duration: 0.28)
                CubicKeyframe(1, duration: 0.08)
                CubicKeyframe(0, duration: 0.14)
                LinearKeyframe(0, duration: 0.28)
                LinearKeyframe(0, duration: 1.9)
            }
            KeyframeTrack(\.level) {
                LinearKeyframe(0.375, duration: 0.45)
                SpringKeyframe(0.4375, duration: 0.5, spring: step)
                SpringKeyframe(0.5, duration: 0.5, spring: step)
                SpringKeyframe(0.5625, duration: 2.35, spring: step)
            }
            KeyframeTrack(\.open) {
                LinearKeyframe(0, duration: 0.45)
                SpringKeyframe(1, duration: 2.45, spring: Spring(duration: 0.45, bounce: 0.3))
                SpringKeyframe(0, duration: 0.9, spring: Spring(duration: 0.4, bounce: 0.1))
            }
        }
    }
}

/// The volume HUD in the notch: the speaker and the bar's track. The level and percentage
/// are layers of their own.
private struct MiniHUD: View {
    static let barWidth = Demo.hud.width - 22

    var body: some View {
        VStack(spacing: 0) {
            WingsLayout(notch: Demo.closed) {
                Image(systemName: "speaker.wave.3.fill", variableValue: 0.5)
                    .font(.system(size: 8, weight: .semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 11)
            } trailing: {
                Color.clear
            }
            .frame(height: Demo.closed.height)
            Capsule()
                .fill(.white.opacity(0.18))
                .frame(width: Self.barWidth, height: 4)
                .frame(maxHeight: .infinity)
        }
        .foregroundStyle(.white)
        .frame(width: Demo.hud.width + 10, height: Demo.hud.height)
    }
}

/// A key of the MacBook's top row, with room around it for its shadow.
private struct DemoKey: View {
    static let margin: CGFloat = 5

    let symbol: String

    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(LinearGradient(colors: [Color(white: 0.17), Color(white: 0.1)], startPoint: .top, endPoint: .bottom))
            .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(.white.opacity(0.1), lineWidth: 0.5) }
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .frame(width: 44, height: 36)
            .shadow(color: .black.opacity(0.5), radius: 1, y: 2)
            .padding(Self.margin)
    }
}
