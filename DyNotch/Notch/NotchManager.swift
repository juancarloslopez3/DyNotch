import AppKit

/// Creates one notch per screen and routes pointer events to them.
final class NotchManager {
    private let services: AppServices
    private let mouse = MouseMonitor()
    private(set) var controllers: [NotchWindowController] = []
    private var screenObserver: NSObjectProtocol?
    private(set) lazy var swipes = NotchSwipeMonitor(settings: services.settings) { [unowned self] in controllers }

    init(services: AppServices) {
        self.services = services
    }

    var primary: NotchViewModel? { controllers.first(where: { $0.model.isPrimary })?.model }
    var models: [NotchViewModel] { controllers.map(\.model) }

    /// Whether `display` has a notch: the primary one's, and every display's while there are
    /// notches on external displays.
    func hasNotch(on display: CGDirectDisplayID) -> Bool {
        controllers.contains { $0.screenID == display }
    }

    func start() {
        rebuild()
        mouse.handler = { [weak self] type, location in
            self?.handleMouse(type, at: location)
        }
        mouse.start()
        swipes.update()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuild() }
        }
    }

    /// Rebuilds the set of notches after screens or settings changed.
    func rebuild() {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }
        let primaryScreen = screens.first(where: { $0.safeAreaInsets.top > 0 && $0.isBuiltIn })
            ?? screens.first(where: { $0.safeAreaInsets.top > 0 })
            ?? NSScreen.main
            ?? screens[0]

        var wanted: [(NSScreen, Bool)] = [(primaryScreen, true)]
        if services.settings.showOnExternalDisplays {
            wanted += screens.filter { $0.displayID != primaryScreen.displayID }.map { ($0, false) }
        }

        var remaining = controllers
        var result: [NotchWindowController] = []
        for (screen, isPrimary) in wanted {
            if let index = remaining.firstIndex(where: { $0.screenID == screen.displayID && $0.model.isPrimary == isPrimary }) {
                let controller = remaining.remove(at: index)
                controller.update(screen: screen)
                result.append(controller)
            } else {
                result.append(NotchWindowController(screen: screen, isPrimary: isPrimary, services: services))
            }
        }
        remaining.forEach { $0.close() }
        controllers = result
        swipes.update()
    }

    private func handleMouse(_ type: NSEvent.EventType, at location: CGPoint) {
        for controller in controllers {
            controller.handleMouse(type, at: location)
        }
        services.drag.handleMouse(type, at: location)
    }

    /// Opens the notch on the primary screen (menu bar "Open Notch").
    func openPrimary(tab: NotchTab? = nil) {
        primary?.open(tab: tab)
    }
}
