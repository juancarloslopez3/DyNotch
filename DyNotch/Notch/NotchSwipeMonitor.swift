import AppKit

/// Acts on swipes over the notch, as set in Settings. Sideways over the open notch moves to the
/// tab beside the current one (Settings › Layout): with two fingers from scroll events, with
/// three from the fingers on the trackpad. Swiping left goes to the next tab, as between Spaces.
/// Down with two fingers over the closed notch opens it, and up over the open one closes it
/// (Settings › General).
final class NotchSwipeMonitor {
    private let settings: AppSettings
    /// The notches, to find the one a swipe is over.
    private let notches: () -> [NotchWindowController]

    private var scrollMonitor: Any?
    private var scrollSwipe = ScrollSwipeRecognizer()
    private let touches = TrackpadTouches()
    private var touchSwipe = TouchSwipeRecognizer()

    init(settings: AppSettings, notches: @escaping () -> [NotchWindowController]) {
        self.settings = settings
        self.notches = notches
        touches.onFrame = { [weak self] frame in self?.handle(frame) }
    }

    /// Listens the way the settings ask: to scrolls all along (DyNotch only gets those over its
    /// own windows), to the trackpad only while a notch is open. Call it when any of them changes.
    func update() {
        let scrolls = settings.tabSwipe == .twoFingers || settings.swipeToOpen
        if scrolls, scrollMonitor == nil {
            scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self else { return event }
                return self.handle(event) ? nil : event
            }
        } else if !scrolls, let scrollMonitor {
            NSEvent.removeMonitor(scrollMonitor)
            self.scrollMonitor = nil
            scrollSwipe = ScrollSwipeRecognizer()
        }

        let listens = settings.tabSwipe == .threeFingers && notches().contains { $0.model.isOpen }
        if listens != touches.isRunning {
            if listens { touches.start() } else { touches.stop() }
            touchSwipe = TouchSwipeRecognizer()
        }
    }

    /// Returns `true` to keep the event from the views under it.
    private func handle(_ event: NSEvent) -> Bool {
        guard let model = notches().first(where: { $0.owns(event.window) })?.model else { return false }
        // With natural scrolling, the content follows the fingers.
        let sign: CGFloat = event.isDirectionInvertedFromDevice ? 1 : -1
        let result = scrollSwipe.update(
            phase: event.phase,
            momentumPhase: event.momentumPhase,
            fingers: CGSize(width: event.scrollingDeltaX * sign, height: event.scrollingDeltaY * sign),
            accepts: { self.accepts($0, over: model, at: event) }
        )
        switch result.swipe {
        case .left: model.swipeTab(by: 1)
        case .right: model.swipeTab(by: -1)
        case .down: model.open()
        case .up:
            model.close()
            Haptics.perform()
        case nil: break
        }
        return result.consumes
    }

    /// Whether a swipe that starts out `direction` over `model`'s notch does something there,
    /// rather than scroll what's under the fingers.
    private func accepts(_ direction: ScrollSwipeRecognizer.Direction, over model: NotchViewModel, at event: NSEvent) -> Bool {
        switch direction {
        case .left, .right:
            model.isOpen && settings.tabSwipe == .twoFingers && !Self.scrolls(.horizontal, at: event)
        case .down:
            !model.isOpen && settings.swipeToOpen
        case .up:
            model.isOpen && settings.swipeToOpen && !Self.scrolls(.vertical, at: event)
        }
    }

    private func handle(_ frame: TrackpadTouches.Frame) {
        guard let step = touchSwipe.update(frame) else { return }
        // Only over the notch, as for two fingers; it may have opened from the menu bar.
        notches().first { $0.model.isOpen && $0.model.isHovering }?.model.swipeTab(by: step)
    }

    /// Whether the event is over something that scrolls along `axis` because it holds more than
    /// fits, such as the Shelf's row sideways or the agenda up and down: the swipe scrolls that
    /// instead.
    private static func scrolls(_ axis: NSLayoutConstraint.Orientation, at event: NSEvent) -> Bool {
        guard let content = event.window?.contentView else { return false }
        let point = content.superview?.convert(event.locationInWindow, from: nil) ?? event.locationInWindow
        var view = content.hitTest(point)
        while let current = view {
            if let scrollView = current as? NSScrollView, let document = scrollView.documentView {
                let visible = scrollView.contentView.bounds
                let overflows = axis == .horizontal
                    ? document.frame.width > visible.width + 1
                    : document.frame.height > visible.height + 1
                if overflows { return true }
            }
            view = current.superview
        }
        return false
    }
}

/// Tells a two-finger swipe from a trackpad's scroll events. Once the fingers have gone
/// `decisionDistance` it decides: mostly sideways, or mostly up or down, and a way `accepts`
/// takes, and it's a swipe, which reports that way after `distance` (once) and keeps the rest of
/// the gesture, momentum included, from the views under it. Anything else scrolls as usual.
nonisolated struct ScrollSwipeRecognizer {
    /// The way the fingers went.
    enum Direction { case left, right, up, down }

    static let decisionDistance: CGFloat = 6
    static let distance: CGFloat = 40

    private enum State: Equatable { case idle, undecided, swiping(Direction), scrolling }
    private var state = State.idle
    private var travel = CGSize.zero
    private var hasMoved = false

    /// Feeds one event. `fingers` is how far they moved, rightward and downward positive.
    /// `accepts` is asked once per gesture, when it decides.
    mutating func update(
        phase: NSEvent.Phase,
        momentumPhase: NSEvent.Phase,
        fingers: CGSize,
        accepts: (Direction) -> Bool
    ) -> (swipe: Direction?, consumes: Bool) {
        if phase.contains(.mayBegin) {
            // Fingers resting before they move, or stopping the last swipe's momentum.
            state = .idle
            return (nil, false)
        }
        if phase.contains(.began) {
            state = .undecided
            travel = .zero
            hasMoved = false
        }
        guard !phase.isEmpty else {
            // Momentum after the fingers lifted, or a mouse wheel (no phases at all).
            return (nil, !momentumPhase.isEmpty && isSwiping)
        }
        guard phase.contains(.began) || phase.contains(.changed) else {
            return (nil, isSwiping)
        }

        travel.width += fingers.width
        travel.height += fingers.height
        if state == .undecided, max(abs(travel.width), abs(travel.height)) >= Self.decisionDistance {
            state = Self.direction(of: travel).flatMap { accepts($0) ? .swiping($0) : nil } ?? .scrolling
        }
        guard case .swiping(let direction) = state else { return (nil, false) }
        if !hasMoved, Self.length(of: travel, toward: direction) >= Self.distance {
            hasMoved = true
            return (direction, true)
        }
        return (nil, true)
    }

    private var isSwiping: Bool {
        if case .swiping = state { true } else { false }
    }

    /// The way `travel` mostly went; nil when it's about as much sideways as up or down.
    private static func direction(of travel: CGSize) -> Direction? {
        if abs(travel.width) > abs(travel.height) * 1.5 { return travel.width < 0 ? .left : .right }
        if abs(travel.height) > abs(travel.width) * 1.5 { return travel.height < 0 ? .up : .down }
        return nil
    }

    /// How far `travel` went `direction`, negative when it went back the other way.
    private static func length(of travel: CGSize, toward direction: Direction) -> CGFloat {
        switch direction {
        case .left: -travel.width
        case .right: travel.width
        case .up: -travel.height
        case .down: travel.height
        }
    }
}

/// Tells a sideways three-finger swipe from the trackpad's frames: once the fingers' middle has
/// gone `distance` (a fraction of the trackpad's width), more sideways than up or down, it moves
/// the tab, once per swipe. The fingers have to come down from fewer; more of them, or a swipe
/// that goes up or down first, is some other gesture.
nonisolated struct TouchSwipeRecognizer {
    static let fingers = 3
    static let distance: CGFloat = 0.1

    /// Where the fingers' middle was when the last of them came down, while it may be a swipe.
    private var origin: CGPoint?
    /// Fewer fingers touched since the last swipe, so the next one can start.
    private var isReady = true

    /// Feeds one frame. Returns +1 for the next tab (the fingers went left), -1 for the previous one.
    mutating func update(_ frame: TrackpadTouches.Frame) -> Int? {
        guard frame.count == Self.fingers else {
            origin = nil
            isReady = frame.count < Self.fingers
            return nil
        }
        guard let origin else {
            if isReady {
                origin = frame.center
                isReady = false
            }
            return nil
        }
        let dx = frame.center.x - origin.x
        let dy = frame.center.y - origin.y
        if abs(dy) >= Self.distance, abs(dy) >= abs(dx) {
            self.origin = nil
            return nil
        }
        guard abs(dx) >= Self.distance, abs(dx) > abs(dy) else { return nil }
        self.origin = nil
        return dx < 0 ? 1 : -1
    }
}

/// A trackpad setting that also acts on three-finger swipes over the notch.
enum TrackpadSwipeConflict {
    /// Swiping between full-screen apps (and Spaces) with three fingers.
    case fullScreenApps
    /// Three-finger drag, which moves the pointer and drags what's under it.
    case threeFingerDrag

    /// Read from the built-in and Magic Trackpad settings, which can change at any time.
    static var current: Self? {
        let domains = ["com.apple.AppleMultitouchTrackpad", "com.apple.driver.AppleBluetoothMultitouch.trackpad"]
            .compactMap(UserDefaults.init(suiteName:))
        if domains.contains(where: { $0.bool(forKey: "TrackpadThreeFingerDrag") }) { return .threeFingerDrag }
        if domains.contains(where: { $0.integer(forKey: "TrackpadThreeFingerHorizSwipeGesture") == 2 }) { return .fullScreenApps }
        return nil
    }

    var message: LocalizedStringResource {
        switch self {
        case .fullScreenApps:
            "macOS also swipes between full-screen apps with three fingers. Set that to four fingers in Trackpad settings › More Gestures."
        case .threeFingerDrag:
            "Three-finger drag is on, so the swipe would drag too. Turn it off in Accessibility settings › Pointer Control, or swipe with two fingers."
        }
    }

    var settingsURL: URL {
        switch self {
        case .fullScreenApps: URL(string: "x-apple.systempreferences:com.apple.Trackpad-Settings.extension")!
        case .threeFingerDrag: URL(string: "x-apple.systempreferences:com.apple.Accessibility-Settings.extension")!
        }
    }
}
