import AppKit
import CoreGraphics

/// Intercepts the volume / brightness / keyboard-illumination keys (and watches Caps Lock and
/// the track keys) with a `CGEventTap`. Consuming a key stops macOS from changing the level and
/// from showing its own HUD. Requires Accessibility permission.
final class MediaKeyTap {
    enum Key: Int {
        case soundUp = 0
        case soundDown = 1
        case brightnessUp = 2
        case brightnessDown = 3
        case mute = 7
        case next = 17
        case previous = 18
        case fast = 19
        case rewind = 20
        case illuminationUp = 21
        case illuminationDown = 22
        case illuminationToggle = 23
    }

    struct Press {
        var key: Key
        var isDown: Bool
        var isRepeat: Bool
        var flags: CGEventFlags
    }

    /// Return `true` to consume the key.
    var onKey: ((Press) -> Bool)?
    var onCapsLock: ((Bool) -> Void)?

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    var isRunning: Bool { tap != nil }

    private static let systemDefinedType: UInt32 = 14
    private static let auxControlButtonsSubtype: Int16 = 8
    private static let capsLockKeyCode: Int64 = 57

    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        let mask: CGEventMask = (1 << Self.systemDefinedType) | (1 << CGEventType.flagsChanged.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: mediaKeyTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }
        self.tap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        tap = nil
        runLoopSource = nil
    }

    /// Returns `true` when the event should be swallowed.
    fileprivate func handle(type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }
        if type == .flagsChanged {
            if event.getIntegerValueField(.keyboardEventKeycode) == Self.capsLockKeyCode {
                onCapsLock?(event.flags.contains(.maskAlphaShift))
            }
            return false
        }
        guard type.rawValue == Self.systemDefinedType,
              let nsEvent = NSEvent(cgEvent: event),
              nsEvent.subtype.rawValue == Self.auxControlButtonsSubtype
        else { return false }

        let data = nsEvent.data1
        let keyCode = (data & 0xFFFF_0000) >> 16
        let keyFlags = data & 0x0000_FFFF
        guard let key = Key(rawValue: keyCode) else { return false }
        let press = Press(
            key: key,
            isDown: ((keyFlags & 0xFF00) >> 8) == 0xA,
            isRepeat: (keyFlags & 0x1) == 1,
            flags: event.flags
        )
        return onKey?(press) ?? false
    }
}

private nonisolated func mediaKeyTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<MediaKeyTap>.fromOpaque(userInfo).takeUnretainedValue()
    nonisolated(unsafe) let event = event
    // The tap's run loop source lives on the main run loop.
    let consumed = MainActor.assumeIsolated {
        tap.handle(type: type, event: event)
    }
    return consumed ? nil : Unmanaged.passUnretained(event)
}
