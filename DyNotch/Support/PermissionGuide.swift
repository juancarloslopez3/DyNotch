import AppKit
import Observation
import SwiftUI

/// Opens a permission's list in System Settings and floats a guide under its window: DyNotch's
/// icon to drag onto the list, or where to turn it on. It follows the window, hides while
/// another app is in front and goes away once the permission is allowed.
final class PermissionGuide {
    static let shared = PermissionGuide()

    private static let settingsBundleID = "com.apple.systempreferences"

    private let model = PermissionGuideModel()
    private var panel: PermissionGuidePanel?
    private weak var center: PermissionCenter?
    private var followTask: Task<Void, Never>?
    private var activationObserver: NSObjectProtocol?
    /// System Settings' main window, once it's on screen.
    private var windowID: CGWindowID?
    private var hasFoundWindow = false

    func show(_ kind: PermissionKind, center: PermissionCenter) {
        self.center = center
        model.kind = kind
        model.step = Self.listsOnlyAddedApps(kind, state: center.state(kind)) ? .drag : .turnOn
        Permissions.openSystemSettings(kind.settingsPane)
        follow()
    }

    /// Whether the guide is up for `kind`, or about to be, waiting for System Settings to open.
    func isGuiding(_ kind: PermissionKind) -> Bool {
        followTask != nil && model.kind == kind
    }

    /// Returns once the guide for `kind` goes away: a moment after it's allowed, when it's
    /// closed, or when another permission's guide takes its place.
    func wait(for kind: PermissionKind) async {
        while isGuiding(kind), !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(250))
        }
    }

    func close() {
        followTask?.cancel()
        followTask = nil
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
        activationObserver = nil
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            panel.animator().alphaValue = 0
        } completionHandler: {
            // Unless another permission's guide brought it back meanwhile.
            MainActor.assumeIsolated {
                if panel.alphaValue == 0 { panel.orderOut(nil) }
            }
        }
    }

    /// Accessibility and Full Disk Access list only the apps added to them, by the + button or a
    /// drop. So does System Audio Recording until DyNotch's prompt has been answered.
    private static func listsOnlyAddedApps(_ kind: PermissionKind, state: PermissionState) -> Bool {
        switch kind {
        case .accessibility, .fullDiskAccess: true
        case .systemAudio: state == .notDetermined
        default: false
        }
    }

    // MARK: - Following System Settings

    private func follow() {
        windowID = nil
        hasFoundWindow = false
        if activationObserver == nil {
            activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.update() }
            }
        }
        followTask?.cancel()
        followTask = Task { [weak self] in
            let start = ContinuousClock.now
            var lastCheck = start
            while !Task.isCancelled {
                guard let self else { return }
                let now = ContinuousClock.now
                if now - lastCheck > .milliseconds(750) {
                    lastCheck = now
                    self.checkPermission()
                }
                // System Settings can take a few seconds to open; give up if it never does.
                if !self.hasFoundWindow, now - start > .seconds(10) {
                    self.close()
                    return
                }
                self.update()
                // Every frame while a button is down, when the window may be dragged. Seldom while
                // the guide is hidden: System Settings coming back to the front shows it right away.
                let interval: Duration = if self.hasFoundWindow, self.panel?.isVisible != true {
                    .seconds(1)
                } else if NSEvent.pressedMouseButtons != 0 {
                    .milliseconds(16)
                } else {
                    .milliseconds(200)
                }
                try? await Task.sleep(for: interval)
            }
        }
    }

    /// Puts the guide under System Settings' window, or hides it while that isn't in front.
    private func update() {
        guard followTask != nil else { return }
        guard let settings = NSRunningApplication.runningApplications(withBundleIdentifier: Self.settingsBundleID).first else {
            if hasFoundWindow { close() }
            return
        }
        guard settings.isActive, let window = settingsWindowFrame(pid: settings.processIdentifier) else {
            hide()
            return
        }
        hasFoundWindow = true
        place(below: window)
    }

    private func checkPermission() {
        guard let center, model.step != .allowed else { return }
        center.refresh()
        guard center.state(model.kind) == .granted else { return }
        withAnimation(.smooth) { model.step = .allowed }
        let task = followTask
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            // Unless another permission's guide took over meanwhile.
            guard let self, self.followTask == task else { return }
            self.close()
        }
    }

    /// The frame of System Settings' main window in AppKit coordinates, if it's on screen.
    private func settingsWindowFrame(pid: pid_t) -> NSRect? {
        if let windowID, let info = Self.windowInfo(.optionIncludingWindow, windowID).first,
           info[kCGWindowOwnerPID as String] as? pid_t == pid {
            return (info[kCGWindowIsOnscreen as String] as? Bool ?? false) ? Self.frame(of: info) : nil
        }
        // Its largest window: sheets and menus are separate, smaller ones.
        let main = Self.windowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            .filter { $0[kCGWindowOwnerPID as String] as? pid_t == pid && $0[kCGWindowLayer as String] as? Int == 0 }
            .compactMap { info in Self.frame(of: info).map { (info, $0) } }
            .max { $0.1.width * $0.1.height < $1.1.width * $1.1.height }
        windowID = main?.0[kCGWindowNumber as String] as? CGWindowID
        return main?.1
    }

    private static func windowInfo(_ options: CGWindowListOption, _ id: CGWindowID) -> [[String: Any]] {
        CGWindowListCopyWindowInfo(options, id) as? [[String: Any]] ?? []
    }

    private static func frame(of info: [String: Any]) -> NSRect? {
        guard let bounds = info[kCGWindowBounds as String] as? NSDictionary,
              let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary),
              let primary = NSScreen.screens.first else { return nil }
        // Window bounds are measured from the top of the primary display, AppKit's from the bottom.
        return NSRect(x: rect.minX, y: primary.frame.maxY - rect.maxY, width: rect.width, height: rect.height)
    }

    // MARK: - Panel

    private func place(below window: NSRect) {
        let panel = self.panel ?? makePanel()
        let size = panel.frame.size
        let visible = (NSScreen.screens.first { $0.frame.intersects(window) } ?? NSScreen.main)?.visibleFrame ?? window
        let margin: CGFloat = 12
        // Centered under the window; over its bottom edge when the screen ends first.
        var origin = NSPoint(x: window.midX - size.width / 2, y: window.minY - margin - size.height)
        origin.x = min(max(origin.x, visible.minX + margin), visible.maxX - size.width - margin)
        origin.y = max(origin.y, visible.minY + margin)
        origin = NSPoint(x: origin.x.rounded(), y: origin.y.rounded())
        if panel.frame.origin != origin { panel.setFrameOrigin(origin) }
        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
        }
        if panel.alphaValue == 0 {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                panel.animator().alphaValue = 1
            }
        }
    }

    private func hide() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> PermissionGuidePanel {
        let view = PermissionGuideView(model: model) { [weak self] in self?.close() }
        let panel = PermissionGuidePanel(rootView: view)
        self.panel = panel
        return panel
    }
}

@Observable
private final class PermissionGuideModel {
    enum Step { case drag, turnOn, allowed }

    var kind = PermissionKind.accessibility
    var step = Step.drag
}

/// Floats above System Settings without ever taking the keyboard from it.
private final class PermissionGuidePanel: NSPanel {
    init(rootView: some View) {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovable = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        animationBehavior = .none
        let controller = NSHostingController(rootView: rootView)
        controller.sizingOptions = .preferredContentSize
        contentViewController = controller
        // Its size before the first placement, which would otherwise go by an empty window.
        setContentSize(controller.view.fittingSize)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - Content

private struct PermissionGuideView: View {
    let model: PermissionGuideModel
    let close: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isIconHovered = false
    @State private var isDragging = false

    var body: some View {
        HStack(spacing: 16) {
            VStack(spacing: 5) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 54, height: 54)
                    .scaleEffect(isIconLifted ? AppIconDragView.liftScale : 1)
                    .offset(y: isIconLifted ? -AppIconDragView.lift : 0)
                    .shadow(color: .black.opacity(isIconLifted ? 0.25 : 0), radius: 4, y: 3)
                    // Dimmed while it's being dragged, as Finder does.
                    .opacity(isDragging ? 0.4 : 1)
                    .overlay {
                        AppIconDragSource(isEnabled: model.step == .drag, isLifted: isIconLifted) { hovering in
                            withAnimation(.spring(duration: 0.35, bounce: 0.45)) { isIconHovered = hovering }
                        } onDrag: { dragging in
                            withAnimation(.smooth(duration: 0.2)) { isDragging = dragging }
                        }
                    }
                Text("DyNotch")
                    .font(.system(size: 12, weight: .medium))
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(title)
                        .font(.system(size: 15, weight: .bold))
                    if model.step == .allowed {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.green)
                            .transition(.blurReplace)
                    } else {
                        BobbingArrow(isMoving: !reduceMotion)
                            .fixedSize()
                            .transition(.blurReplace)
                    }
                }
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(.quaternary, in: .circle)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
        .padding(.leading, 18)
        .padding(.trailing, 16)
        .padding(.vertical, 14)
        .frame(width: 460)
        .glassEffect(.regular, in: .rect(cornerRadius: 26))
    }

    /// The icon rises under the pointer while it can be dragged, ready to be picked up.
    private var isIconLifted: Bool {
        isIconHovered && model.step == .drag && !isDragging && !reduceMotion
    }

    private var title: LocalizedStringKey {
        let kind = model.kind
        return switch model.step {
        case .drag: "Drag DyNotch to the list above"
        case .turnOn where kind == .notifications: "Choose DyNotch in the list above"
        case .turnOn: "Turn on DyNotch in the list above"
        case .allowed: "\(kind.title) is allowed"
        }
    }

    private var message: LocalizedStringKey {
        let kind = model.kind
        return switch model.step {
        case .drag where kind == .systemAudio:
            "Drop it on the System Audio Recording Only list to allow it."
        case .drag:
            "Dropping it there allows \(kind.title)."
        case .turnOn where kind == .notifications:
            "Then turn on Allow Notifications."
        case .turnOn:
            "Switching it on allows \(kind.title)."
        case .allowed:
            "You can close System Settings."
        }
    }
}

/// The arrow pointing up at the list, moving up and back all the time. Core Animation runs it out
/// of process: as a SwiftUI animation it cost ~14% CPU, redrawing the glass every frame.
private struct BobbingArrow: NSViewRepresentable {
    var isMoving: Bool

    func makeNSView(context: Context) -> BobbingArrowView { BobbingArrowView() }

    func updateNSView(_ view: BobbingArrowView, context: Context) {
        view.isMoving = isMoving
    }
}

private final class BobbingArrowView: NSImageView {
    var isMoving = false {
        didSet { updateAnimation() }
    }

    init() {
        super.init(frame: .zero)
        image = NSImage(systemSymbolName: "arrow.up", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 14, weight: .bold))
        contentTintColor = NSColor(Color.accentColor)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateAnimation()
    }

    private func updateAnimation() {
        guard let layer else { return }
        guard isMoving else {
            layer.removeAnimation(forKey: "bob")
            return
        }
        guard layer.animation(forKey: "bob") == nil else { return }
        let bob = CABasicAnimation(keyPath: "transform.translation.y")
        bob.fromValue = 0
        bob.toValue = 5
        bob.duration = 0.45
        bob.autoreverses = true
        bob.repeatCount = .infinity
        bob.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(bob, forKey: "bob")
    }
}

/// DyNotch's icon, which drags the app itself: dropped on a privacy list in System Settings,
/// it adds DyNotch to it.
private struct AppIconDragSource: NSViewRepresentable {
    var isEnabled: Bool
    var isLifted: Bool
    var onHover: (Bool) -> Void
    var onDrag: (Bool) -> Void

    func makeNSView(context: Context) -> AppIconDragView { AppIconDragView() }

    func updateNSView(_ view: AppIconDragView, context: Context) {
        view.isEnabled = isEnabled
        view.isLifted = isLifted
        view.onHover = onHover
        view.onDrag = onDrag
    }
}

/// Takes the mouse over the icon, which SwiftUI draws underneath.
private final class AppIconDragView: NSView, NSDraggingSource {
    /// How much the icon grows and rises while it's lifted.
    static let liftScale: CGFloat = 1.08
    static let lift: CGFloat = 3

    var isEnabled = true
    var isLifted = false
    var onHover: (Bool) -> Void = { _ in }
    var onDrag: (Bool) -> Void = { _ in }
    private var mouseDownEvent: NSEvent?
    private var isHovered = false {
        didSet { if isHovered != oldValue { onHover(isHovered) } }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        // Always active: System Settings, not DyNotch, is in front while the guide is up.
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    required init?(coder: NSCoder) { fatalError() }

    /// The first click on the guide starts a drag even though System Settings is in front.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseEntered(with event: NSEvent) { isHovered = true }

    override func mouseExited(with event: NSEvent) { isHovered = false }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self, name: NSWindow.didChangeOcclusionStateNotification, object: nil)
        guard let window else { return }
        NotificationCenter.default.addObserver(
            self, selector: #selector(refreshHover), name: NSWindow.didChangeOcclusionStateNotification, object: window
        )
    }

    /// No exit comes when the guide hides under the pointer, or while a drag holds the mouse.
    @objc private func refreshHover() {
        guard let window, window.occlusionState.contains(.visible) else {
            isHovered = false
            return
        }
        isHovered = bounds.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil))
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = isEnabled ? event : nil
    }

    override func mouseDragged(with event: NSEvent) {
        guard let down = mouseDownEvent else { return }
        let start = down.locationInWindow, current = event.locationInWindow
        guard hypot(current.x - start.x, current.y - start.y) > 3 else { return }
        mouseDownEvent = nil
        let item = NSDraggingItem(pasteboardWriter: Bundle.main.bundleURL as NSURL)
        item.setDraggingFrame(isLifted ? liftedFrame : bounds, contents: NSApp.applicationIconImage)
        beginDraggingSession(with: [item], event: down, source: self)
    }

    /// Where the lifted icon is drawn, for the drag to pick it up right there. Up is +y here.
    private var liftedFrame: NSRect {
        let width = bounds.width * Self.liftScale, height = bounds.height * Self.liftScale
        return NSRect(x: bounds.midX - width / 2, y: bounds.midY - height / 2 + Self.lift, width: width, height: height)
    }

    override func mouseUp(with event: NSEvent) {
        mouseDownEvent = nil
    }

    // Copy or generic only: never let Finder move DyNotch out of Applications or into the Trash.
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? [.copy, .generic] : []
    }

    func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) {
        onDrag(true)
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        onDrag(false)
        refreshHover()
    }
}
