import AppKit
import SwiftUI

/// Hosting view that never lets SwiftUI resize the panel or apply the notch safe area.
private final class NotchHostingView<Content: View>: NSHostingView<Content> {
    required init(rootView: Content) {
        super.init(rootView: rootView)
        sizingOptions = []
        safeAreaRegions = []
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var safeAreaInsets: NSEdgeInsets { NSEdgeInsetsZero }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Owns the panel and view model for one screen.
final class NotchWindowController {
    let model: NotchViewModel
    let screenID: CGDirectDisplayID
    private let panel: NotchPanel

    init(screen: NSScreen, isPrimary: Bool, services: AppServices) {
        screenID = screen.displayID
        model = NotchViewModel(services: services, geometry: NotchGeometry(screen: screen), isPrimary: isPrimary, screenID: screenID)
        panel = NotchPanel(contentRect: model.windowFrame)
        let root = NotchRootView(model: model).environment(services)
        panel.contentView = NotchHostingView(rootView: root)
        panel.setFrame(model.windowFrame, display: true)
        panel.orderFrontRegardless()
        observePresentation()
    }

    func update(screen: NSScreen) {
        model.geometry = NotchGeometry(screen: screen)
        panel.setFrame(model.windowFrame, display: true)
    }

    func close() {
        panel.orderOut(nil)
        panel.close()
    }

    /// Whether `window` is this notch's panel.
    func owns(_ window: NSWindow?) -> Bool { window === panel }

    func handleMouse(_ type: NSEvent.EventType, at location: CGPoint) {
        model.handleMouse(type, at: location)
        refreshMouseInteractivity(location)
    }

    private func refreshMouseInteractivity(_ location: CGPoint = NSEvent.mouseLocation) {
        let ignores = !model.isInteractive(at: location)
        if panel.ignoresMouseEvents != ignores {
            panel.ignoresMouseEvents = ignores
        }
    }

    /// The shape can grow under a stationary pointer (e.g. a HUD appears, or the Camera tab's
    /// picture grows), so re-check pass-through whenever the presentation or its size changes, or
    /// a bubble comes or goes beside it. Once the notch is no longer open, the keyboard the Shelf
    /// took goes back to the app in front. Three-finger swipes between tabs are only listened for
    /// while a notch is open.
    private func observePresentation() {
        withObservationTracking {
            let presentation = model.presentation
            _ = model.shapeRect(for: presentation)
            _ = model.bubbleRect(for: presentation)
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.refreshMouseInteractivity()
                if self.model.presentation != .open { self.panel.returnKeyboard() }
                self.model.services.notch.swipes.update()
                self.observePresentation()
            }
        }
    }
}
