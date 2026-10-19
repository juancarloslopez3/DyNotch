import AVFoundation
import AppKit
import CoreBluetooth
import CoreLocation
import EventKit
import Observation
import UserNotifications

enum PermissionKind: String, CaseIterable, Identifiable {
    case accessibility, calendars, reminders, location, camera, bluetooth, notifications, systemAudio, fullDiskAccess

    var id: String { rawValue }

    var title: String {
        switch self {
        case .accessibility: String(localized: "Accessibility")
        case .calendars: String(localized: "Calendars")
        case .reminders: String(localized: "Reminders")
        case .location: String(localized: "Location")
        case .camera: String(localized: "Camera")
        case .bluetooth: String(localized: "Bluetooth")
        case .notifications: String(localized: "Notifications")
        case .systemAudio: String(localized: "System Audio Recording")
        case .fullDiskAccess: String(localized: "Full Disk Access")
        }
    }

    var reason: String {
        switch self {
        case .accessibility: String(localized: "Replaces the volume and brightness HUD and shows Caps Lock.")
        case .calendars: String(localized: "Shows upcoming events and the meeting Join button.")
        case .reminders: String(localized: "Shows today's reminders so you can tick them off.")
        case .location: String(localized: "Shows the weather where you are.")
        case .camera: String(localized: "Powers the camera mirror tab.")
        case .bluetooth: String(localized: "Shows when AirPods and other devices connect.")
        case .notifications: String(localized: "Alerts you when a timer finishes.")
        case .systemAudio: String(localized: "Makes the bars beside the notch move with the music. Nothing is recorded.")
        case .fullDiskAccess: String(localized: "Lets DyNotch see Focus mode changes. Optional.")
        }
    }

    var symbol: String {
        switch self {
        case .accessibility: "accessibility"
        case .calendars: "calendar"
        case .reminders: "checklist"
        case .location: "location.fill"
        case .camera: "web.camera.fill"
        case .bluetooth: "dot.radiowaves.left.and.right"
        case .notifications: "bell.badge.fill"
        case .systemAudio: "waveform"
        case .fullDiskAccess: "externaldrive.fill"
        }
    }

    var isRequired: Bool { self == .accessibility }

    /// Whether allowing it takes System Settings: the lists only it can change, and anything
    /// turned down.
    func opensSettings(_ state: PermissionState) -> Bool {
        state == .denied || self == .accessibility || self == .fullDiskAccess
    }

    var settingsPane: Permissions.SettingsPane {
        switch self {
        case .accessibility: .accessibility
        case .calendars: .calendars
        case .reminders: .reminders
        case .location: .location
        case .camera: .camera
        case .bluetooth: .bluetooth
        case .notifications: .notifications
        case .systemAudio: .systemAudio
        case .fullDiskAccess: .fullDiskAccess
        }
    }
}

enum PermissionState {
    case granted, denied, notDetermined
}

/// Live status of every permission DyNotch can use.
@Observable
final class PermissionCenter {
    private(set) var states: [PermissionKind: PermissionState] = [:]
    /// Whether Allow All is going through the permissions.
    private(set) var isAllowingAll = false
    /// The permission Allow All is asking for.
    private(set) var allowingAllKind: PermissionKind?

    @ObservationIgnored private weak var services: AppServices?
    @ObservationIgnored private var bluetoothManager: CBCentralManager?
    @ObservationIgnored private var allowAllTask: Task<Void, Never>?
    @ObservationIgnored private var skipCurrent: (() -> Void)?

    func attach(_ services: AppServices) {
        self.services = services
        refresh()
    }

    func state(_ kind: PermissionKind) -> PermissionState { states[kind] ?? .notDetermined }

    func refresh() {
        var states: [PermissionKind: PermissionState] = [:]
        states[.accessibility] = AXIsProcessTrusted() ? .granted : .notDetermined
        states[.calendars] = Self.state(EKEventStore.authorizationStatus(for: .event))
        states[.reminders] = Self.state(EKEventStore.authorizationStatus(for: .reminder))
        states[.location] = switch services?.weather.location.authorizationStatus ?? .notDetermined {
        case .notDetermined: .notDetermined
        case .denied, .restricted: .denied
        default: .granted
        }
        states[.camera] = switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: .granted
        case .notDetermined: .notDetermined
        default: .denied
        }
        states[.bluetooth] = switch CBManager.authorization {
        case .allowedAlways: .granted
        case .notDetermined: .notDetermined
        default: .denied
        }
        states[.systemAudio] = SystemAudioPermission.state
        states[.fullDiskAccess] = FocusMonitor.hasAccess ? .granted : .notDetermined
        states[.notifications] = self.states[.notifications] ?? .notDetermined
        self.states = states

        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            self.states[.notifications] = switch settings.authorizationStatus {
            case .authorized, .provisional: .granted
            case .denied: .denied
            default: .notDetermined
            }
        }
    }

    private static func state(_ status: EKAuthorizationStatus) -> PermissionState {
        switch status {
        case .fullAccess: .granted
        case .notDetermined: .notDetermined
        default: .denied
        }
    }

    /// Asks for `kind`: the system's prompt, or its list in System Settings with the guide.
    /// Returns once the prompt is answered, or the guide has gone away.
    func request(_ kind: PermissionKind) async {
        if state(kind) == .denied {
            await guide(kind)
        } else {
            await ask(kind)
        }
        if kind == .location, let weather = services?.weather {
            // The weather where you are loads after the answer; turned down, Weather stops using
            // the location.
            Task { await weather.requestLocationAccess() }
        }
    }

    /// The system's prompt for `kind`, or the guide for the lists it never shows one for.
    private func ask(_ kind: PermissionKind) async {
        switch kind {
        case .accessibility, .fullDiskAccess:
            await guide(kind)
        case .calendars:
            await services?.events.requestCalendarAccess()
        case .reminders:
            await services?.events.requestRemindersAccess()
        case .location:
            await services?.weather.location.requestAccess()
        case .camera:
            _ = await AVCaptureDevice.requestAccess(for: .video)
        case .bluetooth:
            // Creating a central manager triggers the system prompt.
            bluetoothManager = CBCentralManager()
            // Start the monitor once the user answers it.
            let deadline = ContinuousClock.now + .seconds(60)
            while CBManager.authorization == .notDetermined, ContinuousClock.now < deadline, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(300))
            }
            if let services { services.bluetooth.startIfAuthorized(services: services) }
        case .notifications:
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        case .systemAudio:
            if await !SystemAudioPermission.request(), SystemAudioPermission.state == .notDetermined {
                await guide(.systemAudio)
            }
            services?.media.updateMeter()
        }
        refresh()
    }

    // MARK: - Allow All

    /// Asks for every permission that isn't allowed yet, one at a time: the system's prompts
    /// first, then the lists only System Settings can change, each with its guide. Each waits for
    /// its answer; closing a guide or Skip moves on. `done` runs once it's been through them all.
    func allowAll(done: @escaping () -> Void = {}) {
        guard !isAllowingAll else { return }
        refresh()
        let pending = PermissionKind.allCases.filter { state($0) != .granted }
        let prompts = pending.filter { !$0.opensSettings(state($0)) }
        let settings = pending.filter { $0.opensSettings(state($0)) }
        isAllowingAll = true
        allowAllTask = Task {
            for kind in prompts + settings {
                // An earlier answer, or System Settings, may have allowed it meanwhile.
                refresh()
                guard !Task.isCancelled else { return }
                guard state(kind) != .granted else { continue }
                allowingAllKind = kind
                await requestUntilSkipped(kind)
            }
            guard !Task.isCancelled else { return }
            endAllowAll()
            done()
        }
    }

    /// Moves Allow All on to the next permission. A prompt stays up (it can't be taken down)
    /// for later; a guide goes away.
    func skipAllowAllKind() {
        if let kind = allowingAllKind, PermissionGuide.shared.isGuiding(kind) {
            PermissionGuide.shared.close()
        }
        skipCurrent?()
    }

    func stopAllowAll() {
        guard isAllowingAll else { return }
        allowAllTask?.cancel()
        skipAllowAllKind()
        endAllowAll()
    }

    private func endAllowAll() {
        allowAllTask = nil
        skipCurrent = nil
        isAllowingAll = false
        allowingAllKind = nil
    }

    /// `request(kind)`, returning early on Skip.
    private func requestUntilSkipped(_ kind: PermissionKind) async {
        let wait = OneTimeWait()
        skipCurrent = { wait.end() }
        Task {
            await request(kind)
            wait.end()
        }
        await wait.value()
    }

    /// Opens the permission's list in System Settings, with a guide under the window to add
    /// DyNotch or turn it on.
    func openSettings(_ kind: PermissionKind) {
        Task { await guide(kind) }
    }

    /// `openSettings`, returning once the guide goes away: the permission allowed, the guide
    /// closed, or another permission's guide shown instead.
    private func guide(_ kind: PermissionKind) async {
        // A rebuilt ad-hoc app keeps its old entry in these lists: the switch stays on but
        // macOS ignores it, and dropping DyNotch there again doesn't replace it. Clearing it
        // first lets the guide's drag add DyNotch afresh. Not allowed means the entry, if
        // any, is of no use anyway.
        switch kind {
        case .accessibility where !Permissions.isAccessibilityTrusted:
            await Permissions.removeFromList("Accessibility")
        case .fullDiskAccess where FocusMonitor.isBlocked:
            await Permissions.removeFromList("SystemPolicyAllFiles")
        default:
            break
        }
        PermissionGuide.shared.show(kind, center: self)
        await PermissionGuide.shared.wait(for: kind)
        refresh()
    }
}

/// A wait that ends the first time `end()` is called, by whichever comes first.
private final class OneTimeWait {
    private var continuation: CheckedContinuation<Void, Never>?
    private var hasEnded = false

    func value() async {
        guard !hasEnded else { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func end() {
        hasEnded = true
        continuation?.resume()
        continuation = nil
    }
}
