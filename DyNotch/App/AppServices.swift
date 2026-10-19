import AppKit
import Observation

/// Owns every long-lived service. Views reach it through the environment.
@Observable
final class AppServices {
    static let shared = AppServices()

    let settings = AppSettings.shared
    let activities = ActivityCenter()
    let media = MediaController()
    let timers = TimerStore()
    let drag = DragMonitor()
    let hud = HUDController()
    let events = EventKitService()
    let weather = WeatherService()
    let focus = FocusMonitor()
    let shelf = ShelfStore()
    @ObservationIgnored let camera = CameraSession()
    let battery = BatteryMonitor()
    @ObservationIgnored let bluetooth = BluetoothMonitor()
    @ObservationIgnored let fullScreen = FullScreenMonitor()
    let permissions = PermissionCenter()

    /// Caps Lock state, kept current by the key tap.
    var capsLockOn = false

    @ObservationIgnored private(set) var notch: NotchManager!

    private init() {
        notch = NotchManager(services: self)
    }

    func start() {
        MenuTracking.start()
        notch.start()
        hud.start(services: self)
        media.start(services: self)
        events.start(services: self)
        weather.start(services: self)
        focus.start(services: self)
        timers.start(services: self)
        battery.start(services: self)
        bluetooth.startIfAuthorized(services: self)
        fullScreen.start(services: self)
        permissions.attach(self)
        drag.services = self
        #if DEBUG
        DebugCommands.start(services: self)
        #endif
    }
}
