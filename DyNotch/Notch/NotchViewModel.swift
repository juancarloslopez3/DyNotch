import AppKit
import Observation

/// Persistent things shown beside a closed notch while they are going on.
enum CompactActivity: Equatable {
    case media
    case timer
    case capsLock
    case clock

    /// Width added on each side of the notch.
    var wing: CGFloat {
        switch self {
        case .media: 44
        case .timer: 64
        case .capsLock: 36
        case .clock: 52
        }
    }

    /// Its bubble beside the notch, while it's the second activity going on: round, or an oval
    /// for a time.
    func bubbleSize(notch: CGSize) -> CGSize {
        let height = notch.height - NotchMetrics.bubbleInset * 2
        return switch self {
        case .timer, .clock: CGSize(width: height + 22, height: height)
        case .media, .capsLock: CGSize(width: height, height: height)
        }
    }

    /// The tab with more about it, while it's in the tab bar: where the notch opens while it's
    /// beside it, and clicking its bubble goes, as tapping one on the iPhone opens its app.
    func tab(in settings: AppSettings) -> NotchTab? {
        switch self {
        case .timer: settings.tab(about: .timer, ownTab: .timers)
        case .media: settings.tab(about: .media)
        case .capsLock, .clock: nil
        }
    }

    /// `active` with those in `order` first, as they were, then the ones that just started: what
    /// is beside the notch keeps its place while other activities come and go after it.
    static func arranged(_ active: [CompactActivity], keeping order: [CompactActivity]) -> [CompactActivity] {
        let staying = order.filter(active.contains)
        return staying + active.filter { !staying.contains($0) }
    }
}

enum NotchPresentation: Equatable {
    case closed
    case peek
    case compact(CompactActivity, hovering: Bool)
    case transient(LiveActivity)
    case open
    case dropTarget

    /// Identity of the content shown, used to drive content transitions.
    var contentID: String {
        switch self {
        case .closed: "closed"
        case .peek: "peek"
        // Hovering only resizes the content, so it keeps the same identity.
        case .compact(let activity, _): "compact-\(activity)"
        case .transient(let activity): "transient-\(activity.id)"
        case .open: "open"
        case .dropTarget: "drop"
        }
    }

    var isExpanded: Bool {
        switch self {
        case .open, .dropTarget: true
        case .transient(let activity):
            if case .expanded = activity.kind.layout(notch: .zero) { true } else { false }
        default: false
        }
    }
}

enum NotchMetrics {
    static let openWidth: CGFloat = 680
    static let openContentHeight: CGFloat = 220
    /// The Camera tab with its large picture: 16:9 across the tab (648 × 364), and the tab's
    /// margins above and below.
    static let largeCameraContentHeight: CGFloat = 388
    static let dropTargetWidth: CGFloat = 460
    static let dropTargetContentHeight: CGFloat = 116
    static let maxTopRadius: CGFloat = 14
    /// How much a compact activity grows (per wing, and in height) while the pointer is over it.
    static let compactHoverGrowth = CGSize(width: 6, height: 5)
    /// A second activity's bubble: how far it stands off the notch, and its margin above and
    /// below within the notch's height.
    static let bubbleGap: CGFloat = 7
    static let bubbleInset: CGFloat = 3
    /// How far anything beside the cut-out stands off the screen, for its shadow (1 once the
    /// notch drops down).
    static let besideNotchElevation: CGFloat = 0.35
    /// Room around the shape inside the window for the drop shadow, so its soft edge isn't
    /// cut off by the window's.
    static let shadowPadding: CGFloat = 64
}

/// State machine for one notch (one per screen).
@Observable
final class NotchViewModel {
    let services: AppServices
    let isPrimary: Bool
    /// The display it's on.
    let screenID: CGDirectDisplayID
    var geometry: NotchGeometry

    private(set) var isOpen = false
    private(set) var isHovering = false
    private(set) var isPeeking = false
    /// The pointer is over the bubble beside the notch. The bubble is a button of its own: it
    /// shows it's ready for a click while the notch stays as it is.
    private(set) var isHoveringBubble = false
    /// A file drag is in progress near this notch.
    var isShowingDropTarget = false
    var isFullScreenActive = false
    /// Bundle identifiers of the apps showing a video full screen on this notch's screen: one,
    /// or two side by side. An app's own window in full screen, toolbar and all (Safari
    /// browsing), doesn't count.
    var fullScreenVideoApps: Set<String> = [] {
        didSet { settleVideoApps() }
    }
    /// The apps in `fullScreenVideoApps` that have been so for `playerFullScreenDelay`.
    private var settledVideoApps: Set<String> = []

    @ObservationIgnored private var hoverTask: Task<Void, Never>?
    @ObservationIgnored private var closeTask: Task<Void, Never>?
    @ObservationIgnored private var settleTask: Task<Void, Never>?
    /// The activities beside the notch in the order they started; see `compactActivities`.
    @ObservationIgnored private var compactOrder: [CompactActivity] = []

    /// How long the player stays beside the notch after its video goes full screen, so it folds
    /// away on the settled video rather than vanishing in the Space's slide.
    static let playerFullScreenDelay: Duration = .seconds(3)

    init(services: AppServices, geometry: NotchGeometry, isPrimary: Bool, screenID: CGDirectDisplayID) {
        self.services = services
        self.geometry = geometry
        self.isPrimary = isPrimary
        self.screenID = screenID
        trackCompactOrder()
    }

    private var settings: AppSettings { services.settings }
    private var suppressedForFullScreen: Bool { isFullScreenActive && settings.hideInFullScreen }

    /// The app playing has been showing a video full screen on this notch's screen for a
    /// moment, so the player stays away from beside the notch.
    var hidesPlayerInFullScreen: Bool {
        guard settings.hidePlayerInFullScreen, let app = services.media.nowPlaying?.bundleIdentifier else { return false }
        return settledVideoApps.contains(app)
    }

    /// Videos leaving full screen bring the player back at once; ones arriving count after
    /// `playerFullScreenDelay`.
    private func settleVideoApps() {
        settledVideoApps.formIntersection(fullScreenVideoApps)
        settleTask?.cancel()
        guard !fullScreenVideoApps.isSubset(of: settledVideoApps) else { return }
        settleTask = Task { [weak self] in
            try? await Task.sleep(for: Self.playerFullScreenDelay)
            guard !Task.isCancelled, let self else { return }
            settledVideoApps = fullScreenVideoApps
        }
    }

    // MARK: - Presentation

    var presentation: NotchPresentation {
        if isShowingDropTarget { return .dropTarget }
        // A ringing alarm comes up over the open notch and in full-screen apps too, so its
        // Stop button is always there.
        if isPrimary, services.timers.isRinging, let activity = services.activities.current,
           case .timerFinished = activity.kind {
            return .transient(activity)
        }
        if isOpen { return .open }
        if let activity = services.activities.current, shows(activity) {
            if !suppressedForFullScreen { return .transient(activity) }
            if case .hud = activity.kind { return .transient(activity) }
        }
        if suppressedForFullScreen { return .closed }
        // A compact activity is already visible and clickable, so hovering grows it rather
        // than swapping it for the (narrower, empty) peek.
        if let compact = compactActivity { return .compact(compact, hovering: isPeeking) }
        if isPeeking { return .peek }
        return .closed
    }

    /// Live activities show in the primary notch, apart from a display's brightness, which shows in
    /// that display's notch when it has one.
    private func shows(_ activity: LiveActivity) -> Bool {
        if case .hud(let snapshot) = activity.kind, case .display(let display)? = snapshot.target,
           services.notch.hasNotch(on: display) {
            return display == screenID
        }
        return isPrimary
    }

    /// What is going on beside the closed notch, in the order it started. Like the Dynamic
    /// Island, the first shows attached to the notch and a second in a bubble of its own beside
    /// it (music playing and a timer running, say); any more wait their turn. The one attached
    /// keeps its place while the others come and go.
    var compactActivities: [CompactActivity] {
        CompactActivity.arranged(activeCompactActivities, keeping: compactOrder)
    }

    /// The activity attached to the notch.
    var compactActivity: CompactActivity? { compactActivities.first }

    /// The second activity going on, in the bubble beside the notch.
    var detachedActivity: CompactActivity? { compactActivities.dropFirst().first }

    /// The activity in the bubble beside the notch in `presentation`: only beside a compact
    /// activity. The bubble flows back into the notch while it opens or shows anything else.
    func bubble(for presentation: NotchPresentation) -> CompactActivity? {
        guard case .compact = presentation else { return nil }
        return detachedActivity
    }

    /// The persistent activities going on, the more important first when they start together.
    private var activeCompactActivities: [CompactActivity] {
        var activities: [CompactActivity] = []
        if services.timers.isRunning { activities.append(.timer) }
        let isPlaying = settings.showCompactMedia && services.media.isActive
        if isPlaying, !hidesPlayerInFullScreen { activities.append(.media) }
        if settings.liveCapsLock, settings.capsLockPersistent, services.capsLockOn { activities.append(.capsLock) }
        // The clock doesn't take the player's place over a full-screen video.
        if activities.isEmpty, !isPlaying, settings.showIdleClock { activities.append(.clock) }
        return activities
    }

    /// Keeps `compactOrder` up to date as activities start and end, notch open or not.
    private func trackCompactOrder() {
        compactOrder = withObservationTracking {
            compactActivities
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.trackCompactOrder() }
        }
    }

    var tab: NotchTab {
        // A hidden tab can't show; fall back to the first one in the tab bar.
        get { settings.visibleTabs.contains(settings.lastTab) ? settings.lastTab : settings.visibleTabs[0] }
        set {
            tabSwipeStep = nil
            settings.lastTab = newValue
        }
    }

    /// The way the tab last changed when it was swiped to, +1 being the next tab, so it slides
    /// in from that side; nil when it was picked any other way.
    private(set) var tabSwipeStep: Int?
    /// Swipes past the first or last tab, which nudge the content the way the fingers went.
    private(set) var tabEdgeBump = TabEdgeBump()

    /// Moves to the tab beside the current one in the tab bar: the next one for +1, the previous
    /// one for -1.
    func swipeTab(by step: Int) {
        let tabs = settings.visibleTabs
        guard isOpen, tabs.count > 1, let index = tabs.firstIndex(of: tab) else { return }
        guard tabs.indices.contains(index + step) else {
            tabEdgeBump = TabEdgeBump(count: tabEdgeBump.count + 1, step: step)
            return
        }
        tab = tabs[index + step]
        tabSwipeStep = step
        Haptics.perform()
    }

    func shapeSize(for presentation: NotchPresentation) -> CGSize {
        let notch = geometry.notchSize
        switch presentation {
        case .closed:
            return notch
        case .peek:
            return CGSize(width: notch.width + 18, height: notch.height + 5)
        case .compact(let activity, let hovering):
            let growth = hovering ? NotchMetrics.compactHoverGrowth : .zero
            return CGSize(width: notch.width + (activity.wing + growth.width) * 2, height: notch.height + growth.height)
        case .transient(let activity):
            switch activity.kind.layout(notch: notch) {
            case .wings(let wing):
                return CGSize(width: notch.width + wing * 2, height: notch.height)
            case .expanded(let width, let extraHeight):
                return CGSize(width: max(width, notch.width), height: notch.height + extraHeight)
            }
        case .open:
            return CGSize(width: NotchMetrics.openWidth, height: notch.height + openContentHeight)
        case .dropTarget:
            return CGSize(width: NotchMetrics.dropTargetWidth, height: notch.height + NotchMetrics.dropTargetContentHeight)
        }
    }

    /// How tall the open notch is below the cut-out: taller on the Camera tab with its large
    /// picture.
    private var openContentHeight: CGFloat {
        tab == .camera && settings.cameraSize == .large ? NotchMetrics.largeCameraContentHeight : NotchMetrics.openContentHeight
    }

    func topRadius(for presentation: NotchPresentation) -> CGFloat {
        switch presentation {
        case .closed: 4
        case .peek, .compact: 6
        case .transient: presentation.isExpanded ? 10 : 6
        case .open, .dropTarget: NotchMetrics.maxTopRadius
        }
    }

    func bottomRadius(for presentation: NotchPresentation) -> CGFloat {
        switch presentation {
        case .closed: 10
        case .peek: 12
        case .compact: shapeSize(for: presentation).height / 2
        case .transient: presentation.isExpanded ? 24 : geometry.notchSize.height / 2
        case .open: 32
        case .dropTarget: 28
        }
    }

    /// The visible shape's rect in global screen coordinates, including the ears.
    func shapeRect(for presentation: NotchPresentation) -> CGRect {
        geometry.rect(for: shapeSize(for: presentation))
            .insetBy(dx: -topRadius(for: presentation), dy: 0)
    }

    /// The bubble's rect in global screen coordinates: off the notch's right side, centred on the
    /// cut-out's height.
    func bubbleRect(for presentation: NotchPresentation) -> CGRect? {
        guard let bubble = bubble(for: presentation) else { return nil }
        let notch = geometry.notchSize
        let size = bubble.bubbleSize(notch: notch)
        return CGRect(
            x: geometry.notchCenterX + shapeSize(for: presentation).width / 2 + NotchMetrics.bubbleGap,
            y: geometry.screenFrame.maxY - (notch.height + size.height) / 2,
            width: size.width,
            height: size.height
        )
    }

    /// Where the pointer is over the bubble: a little around it, since it grows under the pointer.
    private func bubbleTarget(for presentation: NotchPresentation) -> CGRect? {
        bubbleRect(for: presentation)?.insetBy(dx: -3, dy: -3)
    }

    /// Window frame that fits the largest presentation plus shadow room.
    var windowFrame: CGRect {
        let width = NotchMetrics.openWidth + NotchMetrics.maxTopRadius * 2 + NotchMetrics.shadowPadding * 2
        let content = max(NotchMetrics.openContentHeight, NotchMetrics.largeCameraContentHeight)
        let height = geometry.notchSize.height + content + NotchMetrics.shadowPadding
        return CGRect(
            x: geometry.notchCenterX - width / 2,
            y: geometry.screenFrame.maxY - height,
            width: width,
            height: height
        )
    }

    // MARK: - Interaction

    /// Whether the pointer at `location` should interact with the notch (vs. pass through).
    func isInteractive(at location: CGPoint) -> Bool {
        let presentation = presentation
        if presentation == .closed && suppressedForFullScreen { return false }
        return shapeRect(for: presentation).extendedToTop(by: 2).contains(location)
            || bubbleTarget(for: presentation)?.contains(location) == true
    }

    func handleMouse(_ type: NSEvent.EventType, at location: CGPoint) {
        let presentation = presentation
        let rect = shapeRect(for: presentation)
        let hoverRect: CGRect = switch presentation {
        case .closed: rect.insetBy(dx: -8, dy: -4)
        case .open: rect.insetBy(dx: -14, dy: -14)
        default: rect.insetBy(dx: -4, dy: -4)
        }
        // Over the bubble, the notch itself is left alone: it neither peeks nor opens.
        let overBubble = bubbleTarget(for: presentation)?.contains(location) == true
        let inside = !overBubble && hoverRect.extendedToTop(by: 2).contains(location)

        if overBubble != isHoveringBubble {
            isHoveringBubble = overBubble
            // A click opens it, as the notch in click mode, so the tap comes now: the bubble is
            // under the pointer, ready for one.
            if overBubble { Haptics.perform() }
        }
        if inside != isHovering {
            isHovering = inside
            hoverChanged(inside)
        }

        if (type == .leftMouseDown || type == .rightMouseDown) && !inside && isOpen && !NotchAttachments.contains(location) {
            close()
        }
    }

    private func hoverChanged(_ inside: Bool) {
        if inside {
            closeTask?.cancel()
            guard !isOpen, !suppressedForFullScreen else { return }
            // Over a finished timer's alert the pointer is on its way to Again or Stop,
            // which opening would cover.
            if case .transient(let activity) = presentation, case .timerFinished = activity.kind { return }
            isPeeking = true
            guard settings.openMode == .hover else {
                // A click opens it, which the trackpad already feels, so the tap comes now:
                // the notch is under the pointer, ready for one.
                Haptics.perform()
                return
            }
            let delay = settings.hoverDelay
            hoverTask?.cancel()
            hoverTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled, let self, self.isHovering else { return }
                self.open()
            }
        } else {
            hoverTask?.cancel()
            isPeeking = false
            if isOpen { scheduleClose() }
        }
    }

    private func scheduleClose() {
        closeTask?.cancel()
        closeTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(220))
            // Keep the notch open while a mouse button is held (e.g. dragging a file out),
            // or while one of our menus, Quick Look or the share picker is up.
            while NSEvent.pressedMouseButtons != 0 || MenuTracking.isTracking || NotchAttachments.isShowing {
                try? await Task.sleep(for: .milliseconds(120))
                if Task.isCancelled { return }
            }
            guard !Task.isCancelled, let self, !self.isHovering else { return }
            self.close()
        }
    }

    /// Opens the notch on `tab`; without one, on the tab about a live activity in the notch (see
    /// `activityTab()`), else the tab it opens on. A click passes `haptic: false`: the trackpad
    /// already clicked.
    func open(tab: NotchTab? = nil, haptic: Bool = true) {
        hoverTask?.cancel()
        closeTask?.cancel()
        if let tab { self.tab = tab }
        isPeeking = false
        guard !isOpen else { return }
        if tab == nil, let opening = activityTab() ?? settings.effectiveOpeningTab { self.tab = opening }
        isOpen = true
        if haptic { Haptics.perform() }
    }

    /// Opens the notch on the tab about the activity in the bubble, which was clicked: Timers on
    /// the clock that's going, Home for the music.
    func openOnBubble(haptic: Bool = true) {
        open(tab: detachedActivity.flatMap(tab(readiedFor:)), haptic: haptic)
    }

    /// The tab about a live activity in the notch, readied for it, as tapping one on the iPhone
    /// opens its app: the first with a tab in the tab bar of the one showing for a moment, the
    /// one attached to the notch and the one in its bubble.
    private func activityTab() -> NotchTab? {
        if case .transient(let activity) = presentation, let tab = tab(readiedFor: activity.kind) {
            return tab
        }
        for activity in compactActivities.prefix(2) {
            if let tab = tab(readiedFor: activity) { return tab }
        }
        return nil
    }

    /// The tab about `activity`: Timers on the clock that's going for a timer.
    private func tab(readiedFor activity: CompactActivity) -> NotchTab? {
        let tab = activity.tab(in: settings)
        if tab == .timers, let mode = services.timers.compactMode { services.timers.mode = mode }
        return tab
    }

    /// The tab about `activity`: Timers on the clock that finished for its alert.
    private func tab(readiedFor activity: LiveActivityKind) -> NotchTab? {
        let tab = activity.tab(in: settings)
        if tab == .timers, case .timerFinished(let event) = activity { services.timers.mode = event.mode }
        return tab
    }

    func close() {
        hoverTask?.cancel()
        closeTask?.cancel()
        isOpen = false
        isPeeking = false
    }

    func toggle() {
        isOpen ? close() : open()
    }
}

struct TabEdgeBump: Equatable {
    /// Changes with every swipe, so one the same way as the last still counts.
    var count = 0
    var step = 0
}

extension CGRect {
    /// Extends the rect upwards (in AppKit's bottom-left coordinates) so points on the
    /// very top edge of the screen count as inside.
    func extendedToTop(by amount: CGFloat) -> CGRect {
        CGRect(x: minX, y: minY, width: width, height: height + amount)
    }
}
