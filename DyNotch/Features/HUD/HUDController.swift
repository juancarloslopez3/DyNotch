import AppKit
import Observation

enum HUDKind: String, Equatable {
    case volume, brightness, keyboard
}

struct HUDSnapshot: Equatable {
    var kind: HUDKind
    var level: Float
    var isMuted = false
    /// The current output can't be controlled (e.g. HDMI without software volume).
    var isUnavailable = false
    /// For brightness, the displays it's about.
    var target: BrightnessTarget?
    /// Names what's adjusted where it isn't plain to see: the display, when the HUD doesn't show
    /// on it, or all of them.
    var caption: String?

    var symbol: String {
        switch kind {
        case .volume:
            if isUnavailable { return "speaker.badge.exclamationmark.fill" }
            return isMuted || level == 0 ? "speaker.slash.fill" : "speaker.wave.3.fill"
        case .brightness:
            return level < 0.5 ? "sun.min.fill" : "sun.max.fill"
        case .keyboard:
            return level == 0 ? "light.min" : "light.max"
        }
    }

    var displayLevel: Float { isMuted ? 0 : level }
}

/// Replaces the system volume / brightness / keyboard backlight HUD.
@Observable
final class HUDController {
    @ObservationIgnored let volume = VolumeController()
    @ObservationIgnored let displays = DisplayBrightness()
    @ObservationIgnored let keyboard = KeyboardBacklight()
    @ObservationIgnored private let keyTap = MediaKeyTap()
    @ObservationIgnored private weak var services: AppServices?
    @ObservationIgnored private var permissionPoll: Task<Void, Never>?
    @ObservationIgnored private var lastKeyboardLevel: Float = 0.5

    /// Whether the key tap is active (Accessibility granted).
    private(set) var isActive = false

    private static let step: Float = 1 / 16
    private static let fineStep: Float = 1 / 64
    static let hudDuration: TimeInterval = 1.6

    func start(services: AppServices) {
        self.services = services
        keyTap.onKey = { [weak self] press in self?.handle(press) ?? false }
        keyTap.onCapsLock = { [weak self] on in self?.capsLockChanged(on) }
        volume.onChange = { [weak self] in self?.refreshVisibleHUD() }
        volume.start()
        displays.start(settings: services.settings)
        services.capsLockOn = CGEventSource.flagsState(.combinedSessionState).contains(.maskAlphaShift)
        startTapWhenTrusted()
    }

    /// The tap can only be created once Accessibility is granted; keep checking until then.
    private func startTapWhenTrusted() {
        if Permissions.isAccessibilityTrusted, keyTap.start() {
            isActive = true
            return
        }
        permissionPoll?.cancel()
        permissionPoll = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self else { return }
                if Permissions.isAccessibilityTrusted, self.keyTap.start() {
                    self.isActive = true
                    return
                }
            }
        }
    }

    // MARK: - Keys

    private func handle(_ press: MediaKeyTap.Press) -> Bool {
        guard let settings = services?.settings else { return false }
        let fine = press.flags.contains(.maskShift) && press.flags.contains(.maskAlternate)
        // ⌥ alone + a level key opens the matching System Settings pane; leave that to macOS.
        let optionOnly = press.flags.contains(.maskAlternate) && !fine
        let step = fine ? Self.fineStep : Self.step

        switch press.key {
        case .soundUp, .soundDown, .mute:
            guard settings.hudVolume, !optionOnly else { return false }
            if press.isDown { adjustVolume(press.key, step: step) }
            return true

        case .brightnessUp, .brightnessDown:
            let up = press.key == .brightnessUp
            if settings.hudKeyboard, keyboard.isAvailable, matches(settings.backlightModifier, press.flags) {
                if press.isDown { adjustKeyboard(by: up ? step : -step) }
                return true
            }
            guard settings.hudBrightness, !optionOnly, let target = displays.target(for: settings.brightnessKeyScope) else { return false }
            if press.isDown { adjustBrightness(target, by: up ? step : -step) }
            return true

        case .illuminationUp, .illuminationDown, .illuminationToggle:
            guard settings.hudKeyboard, keyboard.isAvailable, !optionOnly else { return false }
            if press.isDown {
                switch press.key {
                case .illuminationUp: adjustKeyboard(by: step)
                case .illuminationDown: adjustKeyboard(by: -step)
                default: toggleKeyboard()
                }
            }
            return true

        case .next, .fast, .previous, .rewind:
            // Left to the player; only noted so the song-change peek slides the right way.
            if press.isDown, !press.isRepeat {
                services?.media.userSkipped(forward: press.key == .next || press.key == .fast)
            }
            return false
        }
    }

    private func matches(_ modifier: BacklightModifier, _ flags: CGEventFlags) -> Bool {
        switch modifier {
        case .control: flags.contains(.maskControl)
        case .option: flags.contains(.maskAlternate)
        case .command: flags.contains(.maskCommand)
        case .none: false
        }
    }

    // MARK: - Adjusting

    private func adjustVolume(_ key: MediaKeyTap.Key, step: Float) {
        guard volume.canSetVolume else {
            show(HUDSnapshot(kind: .volume, level: 0, isUnavailable: true))
            return
        }
        if key == .mute {
            volume.setMuted(!volume.isMuted)
        } else {
            let level = Self.stepped(volume.volume, by: key == .soundUp ? step : -step, step: step)
            volume.setVolume(level)
            if volume.isMuted, key == .soundUp { volume.setMuted(false) }
        }
        show(volumeSnapshot)
    }

    private func adjustBrightness(_ target: BrightnessTarget, by delta: Float) {
        // Each display steps from its own level, so all of them together keep their differences.
        for id in displays.ids(in: target) {
            let current = displays.level(of: id) ?? 0.5
            displays.setLevel(Self.stepped(current, by: delta, step: abs(delta)), of: id)
        }
        show(brightnessSnapshot(target))
    }

    private func adjustKeyboard(by delta: Float) {
        let current = keyboard.brightness() ?? 0
        let level = Self.stepped(current, by: delta, step: abs(delta))
        keyboard.setBrightness(level)
        if level > 0 { lastKeyboardLevel = level }
        show(HUDSnapshot(kind: .keyboard, level: level))
    }

    private func toggleKeyboard() {
        let current = keyboard.brightness() ?? 0
        let level: Float = current > 0 ? 0 : max(lastKeyboardLevel, Self.step)
        if current > 0 { lastKeyboardLevel = current }
        keyboard.setBrightness(level)
        show(HUDSnapshot(kind: .keyboard, level: level))
    }

    /// Moves `value` by `delta`, snapping to the step grid like macOS does.
    static func stepped(_ value: Float, by delta: Float, step: Float) -> Float {
        let snapped = (value / step).rounded() * step
        return min(max(snapped + delta, 0), 1)
    }

    /// Sets a level directly (dragging the HUD bar or a slider in the notch). The HUD's bar passes
    /// the displays it shows as `target`, wherever the pointer went to drag it.
    func set(_ kind: HUDKind, level: Float, target: BrightnessTarget? = nil, showHUD: Bool = true) {
        switch kind {
        case .volume:
            guard volume.canSetVolume else { return }
            volume.setVolume(level)
            if level > 0, volume.isMuted { volume.setMuted(false) }
        case .brightness:
            guard let target = target ?? brightnessTarget else { return }
            for id in displays.ids(in: target) { displays.setLevel(level, of: id) }
        case .keyboard:
            keyboard.setBrightness(level)
            if level > 0 { lastKeyboardLevel = level }
        }
        if showHUD { show(snapshot(for: kind, target: target)) }
    }

    func snapshot(for kind: HUDKind, target: BrightnessTarget? = nil) -> HUDSnapshot {
        switch kind {
        case .volume: volumeSnapshot
        case .brightness: (target ?? brightnessTarget).map(brightnessSnapshot) ?? HUDSnapshot(kind: .brightness, level: 0)
        case .keyboard: HUDSnapshot(kind: .keyboard, level: keyboard.brightness() ?? 0)
        }
    }

    /// What the brightness keys adjust now.
    private var brightnessTarget: BrightnessTarget? {
        services.flatMap { displays.target(for: $0.settings.brightnessKeyScope) }
    }

    private func brightnessSnapshot(_ target: BrightnessTarget) -> HUDSnapshot {
        HUDSnapshot(kind: .brightness, level: displays.level(of: target.lead) ?? 0, target: target, caption: caption(for: target))
    }

    /// With more than one display to adjust, the HUD names the display it's about when it shows
    /// in another one's notch, or says it's about all of them.
    private func caption(for target: BrightnessTarget) -> String? {
        guard displays.connected.count(where: \.isAdjustable) > 1 else { return nil }
        switch target {
        case .all:
            return String(localized: "All Displays")
        case .display(let id):
            return services?.notch.hasNotch(on: id) == true ? nil : displays.name(of: id)
        }
    }

    private var volumeSnapshot: HUDSnapshot {
        HUDSnapshot(kind: .volume, level: volume.volume, isMuted: volume.isMuted, isUnavailable: !volume.canSetVolume)
    }

    private func show(_ snapshot: HUDSnapshot) {
        services?.activities.post(LiveActivity(id: "hud", kind: .hud(snapshot), duration: Self.hudDuration))
    }

    /// Keeps a visible volume HUD in sync with changes made elsewhere (e.g. Control Center).
    private func refreshVisibleHUD() {
        guard let activities = services?.activities,
              case .hud(let snapshot)? = activities.current?.kind,
              snapshot.kind == .volume
        else { return }
        let fresh = volumeSnapshot
        activities.update(id: "hud") { $0.kind = .hud(fresh) }
    }

    // MARK: - Caps Lock

    private func capsLockChanged(_ on: Bool) {
        guard let services, services.capsLockOn != on else { return }
        services.capsLockOn = on
        if services.settings.liveCapsLock {
            services.activities.post(LiveActivity(id: "capslock", kind: .capsLock(on), duration: 1.5))
        }
    }
}
