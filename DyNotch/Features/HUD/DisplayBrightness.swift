import AppKit
import Observation

/// What one brightness change goes to.
enum BrightnessTarget: Equatable {
    /// A display, and any display mirroring it or that it mirrors.
    case display(CGDirectDisplayID)
    /// Every display that can be adjusted. `lead`, the one with the pointer, is the one whose
    /// level the HUD shows.
    case all(lead: CGDirectDisplayID)

    var lead: CGDirectDisplayID {
        switch self {
        case .display(let id), .all(let id): id
        }
    }
}

/// A connected display, as the brightness controls see it.
struct BrightnessDisplay: Identifiable, Equatable {
    enum Control: Equatable {
        /// Through DisplayServices, as macOS does it: the built-in display and Apple's own.
        case native
        /// Over DDC/CI, through the display's cable: most other monitors.
        case ddc
        /// Neither: AirPlay, Sidecar, DisplayLink and the like.
        case none
    }

    let id: CGDirectDisplayID
    var name: String
    var isBuiltIn: Bool
    var control: Control
    /// From 0 to 1; nil while it isn't known.
    var level: Float?
    /// Over DDC/CI: whether the display answered when asked for its brightness, nil until it has
    /// been asked. Some never do, yet take new levels all the same.
    var answered: Bool?

    var isAdjustable: Bool { control != .none }
}

/// The brightness of every display: the built-in one and Apple's through DisplayServices, other
/// monitors over DDC/CI, as MonitorControl does. DDC/CI is slow, so a monitor's level here is the
/// one last set or read, and its channel sends the newest in the background.
@Observable
final class DisplayBrightness {
    /// Every display connected, the built-in one first.
    private(set) var connected: [BrightnessDisplay] = []

    /// A monitor adjusted over DDC/CI.
    private struct Monitor {
        let channel: DDCChannel
        /// The top of its brightness scale, as it says when asked: 100 until then, as on almost
        /// every display.
        var maximum: UInt16 = 100
        /// Counts the changes made from here, so that a read under way meanwhile can't undo one.
        var changes = 0
    }

    @ObservationIgnored private var monitors: [CGDirectDisplayID: Monitor] = [:]
    @ObservationIgnored private var settings: AppSettings?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private var reconnectsOnScan = false
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    func start(settings: AppSettings) {
        self.settings = settings
        // Apple's displays right away, other monitors once their channels are found.
        apply([], reconnecting: false)
        scan()
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scan(after: .milliseconds(500)) }
        })
        // After sleep every channel starts afresh, and a display waking up takes a moment to answer.
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scan(after: .seconds(3), reconnecting: true) }
            })
        }
    }

    // MARK: - Levels

    /// A display's brightness from 0 to 1, or nil if it isn't known.
    func level(of id: CGDirectDisplayID) -> Float? {
        guard let display = connected.first(where: { $0.id == id }) else { return nil }
        // macOS changes its own displays' too (auto-brightness, Control Center).
        return display.control == .native ? DisplayServices.brightness(of: id) ?? display.level : display.level
    }

    func setLevel(_ level: Float, of id: CGDirectDisplayID) {
        guard let index = connected.firstIndex(where: { $0.id == id }) else { return }
        let level = min(max(level, 0), 1)
        switch connected[index].control {
        case .native:
            DisplayServices.setBrightness(level, of: id)
        case .ddc:
            guard var monitor = monitors[id] else { return }
            monitor.changes += 1
            monitors[id] = monitor
            monitor.channel.write(DDC.brightness, value: UInt16((level * Float(monitor.maximum)).rounded()))
            scheduleSave()
        case .none:
            return
        }
        connected[index].level = level
    }

    func name(of id: CGDirectDisplayID) -> String? {
        connected.first { $0.id == id }?.name
    }

    /// Brings the levels up to date, for Settings: macOS changes its displays' too (auto-brightness,
    /// Control Center), and a monitor's own buttons change its.
    func refresh() {
        for index in connected.indices {
            let display = connected[index]
            switch display.control {
            case .native:
                connected[index].level = DisplayServices.brightness(of: display.id) ?? display.level
            case .ddc where display.answered == true:
                readLevel(of: display.id, retrying: false)
            default:
                break
            }
        }
    }

    // MARK: - Targets

    /// What the brightness keys adjust when set to `scope`, or nil when it's no display DyNotch
    /// can adjust, so the keys go on to macOS.
    func target(for scope: BrightnessKeyScope) -> BrightnessTarget? {
        let builtIn = connected.first { $0.isBuiltIn && $0.isAdjustable }?.id
        switch scope {
        case .builtIn:
            return builtIn.map { .display($0) }
        case .pointer:
            // With the pointer on a display that can't be adjusted (AirPlay, Sidecar…), the keys
            // adjust the built-in display, as they always did.
            return (Self.displayUnderPointer().flatMap(adjustable(showing:)) ?? builtIn).map { .display($0) }
        case .all:
            let lead = Self.displayUnderPointer().flatMap(adjustable(showing:)) ?? connected.first(where: \.isAdjustable)?.id
            return lead.map { .all(lead: $0) }
        }
    }

    /// The displays a change for `target` goes to.
    func ids(in target: BrightnessTarget) -> [CGDirectDisplayID] {
        switch target {
        case .display(let id): mirrorSet(of: id)
        case .all: connected.filter(\.isAdjustable).map(\.id)
        }
    }

    /// A display that can be adjusted showing what `id` shows: `id` itself, or one in its mirror set.
    private func adjustable(showing id: CGDirectDisplayID) -> CGDirectDisplayID? {
        mirrorSet(of: id).first
    }

    /// The displays that can be adjusted showing what `id` shows, `id` first: itself, any
    /// mirroring it and any it mirrors.
    private func mirrorSet(of id: CGDirectDisplayID) -> [CGDirectDisplayID] {
        let set = connected.filter { $0.isAdjustable && Self.source($0.id) == Self.source(id) }.map(\.id)
        return set.contains(id) ? [id] + set.filter { $0 != id } : set
    }

    /// The display `id` mirrors, or `id` itself if it mirrors none.
    private static func source(_ id: CGDirectDisplayID) -> CGDirectDisplayID {
        let mirrored = CGDisplayMirrorsDisplay(id)
        return mirrored == kCGNullDirectDisplay ? id : mirrored
    }

    private static func displayUnderPointer() -> CGDirectDisplayID? {
        guard let point = CGEvent(source: nil)?.location else { return nil }
        var id = kCGNullDirectDisplay
        var count: UInt32 = 0
        guard CGGetDisplaysWithPoint(point, 1, &id, &count) == .success, count > 0 else { return nil }
        return id
    }

    // MARK: - Finding displays

    /// Looks for displays again after `delay`, so that a burst of screen changes makes one scan.
    /// `reconnecting` opens every monitor's channel afresh, as after sleep.
    private func scan(after delay: Duration = .zero, reconnecting: Bool = false) {
        reconnectsOnScan = reconnectsOnScan || reconnecting
        scanTask?.cancel()
        scanTask = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            let channels = await Task.detached(priority: .userInitiated) { DDCChannel.discover() }.value
            guard !Task.isCancelled else { return }
            apply(channels, reconnecting: reconnectsOnScan)
            reconnectsOnScan = false
        }
    }

    private func apply(_ channels: [DDCChannel], reconnecting: Bool) {
        let ids = Self.connectedIDs()
        let native = Set(ids.filter { DisplayServices.canChangeBrightness(of: $0) })
        // A monitor's channel is the one on its framebuffer.
        var unclaimed = channels
        var claimed: [CGDirectDisplayID: DDCChannel] = [:]
        var unplaced: [CGDirectDisplayID] = []
        for id in ids where CGDisplayIsBuiltin(id) == 0 && !native.contains(id) && !CoreDisplay.isVirtual(id) {
            if let path = CoreDisplay.framebufferPath(of: id), let index = unclaimed.firstIndex(where: { $0.framebuffer == path }) {
                claimed[id] = unclaimed.remove(at: index)
            } else {
                unplaced.append(id)
            }
        }
        // Without CoreDisplay's word, a lone monitor can still only be on the lone channel left.
        if unplaced.count == 1, unclaimed.count == 1 { claimed[unplaced[0]] = unclaimed[0] }

        var next: [CGDirectDisplayID: Monitor] = [:]
        var reading: [CGDirectDisplayID] = []
        for (id, channel) in claimed {
            // A monitor still on the same channel keeps using it, so nothing it's sending crosses
            // a new one on the wire.
            if !reconnecting, let monitor = monitors[id],
               monitor.channel.framebuffer == channel.framebuffer, monitor.channel.route == channel.route {
                next[id] = monitor
            } else {
                next[id] = Monitor(channel: channel, maximum: monitors[id]?.maximum ?? 100)
                reading.append(id)
            }
        }
        monitors = next

        connected = ids.map { id in
            let previous = connected.first { $0.id == id }
            var display = BrightnessDisplay(id: id, name: Self.name(of: id), isBuiltIn: CGDisplayIsBuiltin(id) != 0, control: .none)
            if native.contains(id) {
                display.control = .native
                display.level = DisplayServices.brightness(of: id)
            } else if next[id] != nil {
                display.control = .ddc
                display.level = previous?.level ?? savedLevel(of: id)
                display.answered = reading.contains(id) ? nil : previous?.answered
            }
            return display
        }
        reading.forEach { readLevel(of: $0) }
    }

    /// Asks a monitor for its brightness. One that doesn't answer is asked once more a little
    /// later, as one just connected or woken up can take a moment.
    private func readLevel(of id: CGDirectDisplayID, retrying: Bool = true) {
        guard let monitor = monitors[id] else { return }
        Task {
            let value = await monitor.channel.read(DDC.brightness)
            // Unless the monitor went, or was found afresh, meanwhile.
            guard monitors[id]?.channel === monitor.channel, let index = connected.firstIndex(where: { $0.id == id }) else { return }
            guard let value else {
                if retrying {
                    try? await Task.sleep(for: .seconds(5))
                    if monitors[id]?.channel === monitor.channel { readLevel(of: id, retrying: false) }
                } else {
                    connected[index].answered = false
                }
                return
            }
            connected[index].answered = true
            monitors[id]?.maximum = value.maximum
            // A change made meanwhile is newer than what the monitor said.
            if monitors[id]?.changes == monitor.changes {
                connected[index].level = min(Float(value.current) / Float(value.maximum), 1)
                scheduleSave()
            }
        }
    }

    /// The displays connected, the built-in one first: every one online, those mirroring another
    /// too, but the built-in one only while it's on (not with the lid closed).
    private static func connectedIDs() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success else { return [] }
        var ids = [CGDirectDisplayID](repeating: kCGNullDirectDisplay, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return [] }
        let online = ids.prefix(Int(count))
        return online.filter { CGDisplayIsBuiltin($0) != 0 && CGDisplayIsActive($0) != 0 }
            + online.filter { CGDisplayIsBuiltin($0) == 0 }
    }

    /// The name System Settings gives it. One mirroring another has no screen of its own, so its
    /// product name.
    private static func name(of id: CGDirectDisplayID) -> String {
        NSScreen.screens.first { $0.displayID == id }?.localizedName
            ?? CoreDisplay.productName(of: id)
            ?? String(localized: "Display", comment: "The name of a display that has none")
    }

    // MARK: - Saving

    /// The level last set on a monitor, for one that doesn't say its own.
    private func savedLevel(of id: CGDirectDisplayID) -> Float? {
        settings?.externalBrightness[Self.key(of: id)].map(Float.init)
    }

    /// Keeps the monitors' levels for the next launch: a moment after the last change, rather than
    /// at every step of a drag.
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, let settings else { return }
            var levels = settings.externalBrightness
            for display in connected where display.control == .ddc {
                if let level = display.level { levels[Self.key(of: display.id)] = Double(level) }
            }
            settings.externalBrightness = levels
        }
    }

    /// A monitor across launches and reconnections: its vendor, model and serial number.
    private static func key(of id: CGDirectDisplayID) -> String {
        "\(CGDisplayVendorNumber(id))-\(CGDisplayModelNumber(id))-\(CGDisplaySerialNumber(id))"
    }
}
