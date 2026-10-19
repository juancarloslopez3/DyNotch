import AppKit
import IOKit
import ObjectiveC

/// Thin wrappers around private system frameworks, loaded at runtime so the app keeps
/// working (with the feature disabled) if Apple removes a symbol.
nonisolated enum PrivateFrameworks {
    static func load(_ path: String) -> UnsafeMutableRawPointer? {
        dlopen(path, RTLD_NOW)
    }
}

/// Display brightness via DisplayServices, as macOS's own brightness keys set it: the built-in
/// display's, and that of Apple's external displays (and LG's UltraFine).
enum DisplayServices {
    private typealias GetFunction = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetFunction = @convention(c) (CGDirectDisplayID, Float) -> Int32
    private typealias HDRFunction = @convention(c) (CGDirectDisplayID) -> Bool

    private static let handle = PrivateFrameworks.load("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices")
    private static let getFunction = dlsym(handle, "DisplayServicesGetBrightness").map { unsafeBitCast($0, to: GetFunction.self) }
    private static let setFunction = dlsym(handle, "DisplayServicesSetBrightness").map { unsafeBitCast($0, to: SetFunction.self) }
    private static let skyLight = PrivateFrameworks.load("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight")
    private static let hdrSupportedFunction = dlsym(skyLight, "CGSIsHDRSupported").map { unsafeBitCast($0, to: HDRFunction.self) }
    private static let hdrEnabledFunction = dlsym(skyLight, "CGSIsHDREnabled").map { unsafeBitCast($0, to: HDRFunction.self) }
    /// Apple's vendor number in a display's EDID.
    private static let appleVendor: UInt32 = 0x0610

    /// Whether DisplayServices sets `display`'s brightness: one it can tell the brightness of, as
    /// MonitorControl decides. Since macOS 15 it also tells that of other makers' displays showing
    /// HDR, which it only dims in software, so those don't count.
    static func canChangeBrightness(of display: CGDirectDisplayID) -> Bool {
        guard setFunction != nil else { return false }
        if CGDisplayIsBuiltin(display) != 0 { return true }
        if CGDisplayVendorNumber(display) != appleVendor,
           hdrSupportedFunction?(display) == true, hdrEnabledFunction?(display) == true {
            return false
        }
        return brightness(of: display) != nil
    }

    static func brightness(of display: CGDirectDisplayID) -> Float? {
        var value: Float = -1
        guard let getFunction, getFunction(display, &value) == 0, value >= 0 else { return nil }
        return value
    }

    static func setBrightness(_ value: Float, of display: CGDirectDisplayID) {
        _ = setFunction?(display, min(max(value, 0), 1))
    }
}

/// What CoreDisplay knows of a display, through its private
/// `CoreDisplay_DisplayCreateInfoDictionary`.
enum CoreDisplay {
    private typealias InfoFunction = @convention(c) (CGDirectDisplayID) -> Unmanaged<CFDictionary>?

    private static let handle = PrivateFrameworks.load("/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay")
    private static let infoFunction = dlsym(handle, "CoreDisplay_DisplayCreateInfoDictionary").map { unsafeBitCast($0, to: InfoFunction.self) }

    private static func info(_ display: CGDirectDisplayID) -> [String: Any]? {
        infoFunction?(display)?.takeRetainedValue() as? [String: Any]
    }

    /// The I/O Registry path of the framebuffer showing `display`, e.g.
    /// `IOService:/AppleARMPE/arm-io/AppleT600xIO/dispext0@88000000/AppleCLCD2`.
    static func framebufferPath(of display: CGDirectDisplayID) -> String? {
        info(display)?["IODisplayLocation"] as? String
    }

    /// Whether `display` is made up by software (AirPlay, Sidecar, DisplayLink…) rather than at the
    /// end of a cable.
    static func isVirtual(_ display: CGDirectDisplayID) -> Bool {
        guard let info = info(display) else { return false }
        return info["kCGDisplayIsVirtualDevice"] as? Bool ?? info["kCGDisplayIsAirPlay"] as? Bool ?? false
    }

    /// The display's product name, in the app's language where the display has it.
    static func productName(of display: CGDirectDisplayID) -> String? {
        guard let names = info(display)?["DisplayProductName"] as? [String: String] else { return nil }
        return names[Locale.current.identifier] ?? names["en_US"] ?? names.values.first
    }
}

/// The AV service Apple silicon gives an external display, through IOKit's private IOAVService
/// calls: its I²C bus, which DDC/CI goes over. Used from one queue at a time.
nonisolated final class IOAVService: I2CBus, @unchecked Sendable {
    private typealias CreateFunction = @convention(c) (CFAllocator?, io_service_t) -> Unmanaged<CFTypeRef>?
    private typealias I2CFunction = @convention(c) (CFTypeRef, UInt32, UInt32, UnsafeMutableRawPointer, UInt32) -> IOReturn

    private struct Functions {
        let create: CreateFunction
        let read: I2CFunction
        let write: I2CFunction
    }

    private static let functions: Functions? = {
        let handle = PrivateFrameworks.load("/System/Library/Frameworks/IOKit.framework/IOKit")
        guard let create = dlsym(handle, "IOAVServiceCreateWithService"),
              let read = dlsym(handle, "IOAVServiceReadI2C"),
              let write = dlsym(handle, "IOAVServiceWriteI2C")
        else { return nil }
        return Functions(
            create: unsafeBitCast(create, to: CreateFunction.self),
            read: unsafeBitCast(read, to: I2CFunction.self),
            write: unsafeBitCast(write, to: I2CFunction.self)
        )
    }()

    private let functions: Functions
    private let entry: io_service_t
    private let service: CFTypeRef

    /// The service of the registry `entry`, a `DCPAVServiceProxy`.
    init?(_ entry: io_service_t) {
        guard let functions = Self.functions,
              let service = functions.create(kCFAllocatorDefault, entry)?.takeRetainedValue()
        else { return nil }
        self.functions = functions
        // Held for as long as the service, which doesn't say whether it holds the entry itself.
        IOObjectRetain(entry)
        self.entry = entry
        self.service = service
    }

    deinit {
        IOObjectRelease(entry)
    }

    func write(_ bytes: [UInt8], to address: UInt8, offset: UInt8) -> Bool {
        var bytes = bytes
        return functions.write(service, UInt32(address), UInt32(offset), &bytes, UInt32(bytes.count)) == kIOReturnSuccess
    }

    func read(_ count: Int, from address: UInt8, offset: UInt8) -> [UInt8]? {
        var bytes = [UInt8](repeating: 0, count: count)
        let result = functions.read(service, UInt32(address), UInt32(offset), &bytes, UInt32(count))
        return result == kIOReturnSuccess ? bytes : nil
    }
}

/// Keyboard backlight via CoreBrightness' `KeyboardBrightnessClient`.
final class KeyboardBacklight {
    private typealias GetFunction = @convention(c) (AnyObject, Selector, UInt64) -> Float
    private typealias SetFunction = @convention(c) (AnyObject, Selector, Float, UInt64) -> ObjCBool
    private typealias BoolFunction = @convention(c) (AnyObject, Selector, UInt64) -> ObjCBool

    private let client: NSObject?
    private let keyboardID: UInt64?

    init() {
        _ = PrivateFrameworks.load("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness")
        guard let type = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type else {
            client = nil
            keyboardID = nil
            return
        }
        let client = type.init()
        self.client = client

        let idsSelector = NSSelectorFromString("copyKeyboardBacklightIDs")
        let ids = (client.responds(to: idsSelector) ? client.perform(idsSelector)?.takeRetainedValue() as? [NSNumber] : nil) ?? []
        let builtInSelector = NSSelectorFromString("isKeyboardBuiltIn:")
        let builtIn = ids.first { id in
            guard let function: BoolFunction = Self.method(client, builtInSelector) else { return false }
            return function(client, builtInSelector, id.uint64Value).boolValue
        }
        keyboardID = (builtIn ?? ids.first)?.uint64Value
    }

    var isAvailable: Bool { client != nil && keyboardID != nil }

    func brightness() -> Float? {
        let selector = NSSelectorFromString("brightnessForKeyboard:")
        guard let client, let keyboardID, let function: GetFunction = Self.method(client, selector) else { return nil }
        return function(client, selector, keyboardID)
    }

    func setBrightness(_ value: Float) {
        let selector = NSSelectorFromString("setBrightness:forKeyboard:")
        guard let client, let keyboardID, let function: SetFunction = Self.method(client, selector) else { return }
        _ = function(client, selector, min(max(value, 0), 1), keyboardID)
    }

    private static func method<T>(_ object: NSObject, _ selector: Selector) -> T? {
        guard let method = class_getInstanceMethod(type(of: object), selector) else { return nil }
        return unsafeBitCast(method_getImplementation(method), to: T.self)
    }
}

/// The Space each display shows, from SkyLight (what Mission Control reads). An app in full
/// screen gets a Space of its own, which names the app.
enum DisplaySpaces {
    private typealias ConnectionFunction = @convention(c) () -> Int32
    private typealias CopySpacesFunction = @convention(c) (Int32) -> Unmanaged<CFArray>?

    private static let handle = PrivateFrameworks.load("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight")
    private static let connection = dlsym(handle, "SLSMainConnectionID").map { unsafeBitCast($0, to: ConnectionFunction.self)() }
    private static let copySpaces = dlsym(handle, "SLSCopyManagedDisplaySpaces").map { unsafeBitCast($0, to: CopySpacesFunction.self) }

    /// Each display's current Space, keyed by the display's UUID, or by "Main" for every display
    /// when they share their Spaces. Empty if SkyLight can't be read.
    static func current() -> [String: [String: Any]] {
        guard let connection, let copySpaces,
              let displays = copySpaces(connection)?.takeRetainedValue() as? [[String: Any]]
        else { return [:] }
        var spaces: [String: [String: Any]] = [:]
        for display in displays {
            if let id = display["Display Identifier"] as? String, let space = display["Current Space"] as? [String: Any] {
                spaces[id] = space
            }
        }
        return spaces
    }
}

/// Matches Accessibility's windows to the window server's, through HIServices' private
/// `_AXUIElementGetWindow`; there's no public way to.
enum AccessibilityWindows {
    private typealias GetWindowFunction = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError

    private static let handle = PrivateFrameworks.load("/System/Library/Frameworks/ApplicationServices.framework/Frameworks/HIServices.framework/HIServices")
    private static let getWindow = dlsym(handle, "_AXUIElementGetWindow").map { unsafeBitCast($0, to: GetWindowFunction.self) }

    /// The window number the window list and SkyLight know `window` by.
    static func windowID(of window: AXUIElement) -> CGWindowID? {
        var id: CGWindowID = kCGNullWindowID
        guard let getWindow, getWindow(window, &id) == .success, id != kCGNullWindowID else { return nil }
        return id
    }
}

extension AXUIElement {
    nonisolated func attribute<T>(_ name: String) -> T? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(self, name as CFString, &value) == .success else { return nil }
        return value as? T
    }
}

/// The fingers on the trackpads, read raw from MultitouchSupport. macOS hands apps three-finger
/// swipes as events only when it's set to swipe between pages with them, so this is how the
/// notch sees them. No permission is needed. Listening wakes DyNotch for every frame (~125 a
/// second while anything touches a trackpad), so it's only on while it's needed.
final class TrackpadTouches {
    /// The fingers in contact in one frame, and their middle, from 0 to 1 across the trackpad
    /// from its bottom left corner.
    nonisolated struct Frame: Sendable, Equatable {
        var count: Int
        var center: CGPoint
    }

    typealias Callback = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Int32, Double, Int32) -> Int32
    private typealias CreateListFunction = @convention(c) () -> Unmanaged<CFMutableArray>?
    private typealias RegisterFunction = @convention(c) (UnsafeMutableRawPointer, Callback) -> Void
    private typealias StartFunction = @convention(c) (UnsafeMutableRawPointer, Int32) -> Void
    private typealias StopFunction = @convention(c) (UnsafeMutableRawPointer) -> Void

    /// Called on the main thread with each frame.
    var onFrame: ((Frame) -> Void)?

    /// The listener the callback, which has no context, hands frames to.
    fileprivate static weak var current: TrackpadTouches?

    private let createList: CreateListFunction?
    private let register: RegisterFunction?
    private let unregister: RegisterFunction?
    private let startDevice: StartFunction?
    private let stopDevice: StopFunction?
    /// The trackpads listened to; releasing the list releases them.
    private var devices: CFArray?

    init() {
        let handle = PrivateFrameworks.load("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport")
        createList = dlsym(handle, "MTDeviceCreateList").map { unsafeBitCast($0, to: CreateListFunction.self) }
        register = dlsym(handle, "MTRegisterContactFrameCallback").map { unsafeBitCast($0, to: RegisterFunction.self) }
        unregister = dlsym(handle, "MTUnregisterContactFrameCallback").map { unsafeBitCast($0, to: RegisterFunction.self) }
        startDevice = dlsym(handle, "MTDeviceStart").map { unsafeBitCast($0, to: StartFunction.self) }
        stopDevice = dlsym(handle, "MTDeviceStop").map { unsafeBitCast($0, to: StopFunction.self) }
    }

    var isRunning: Bool { devices != nil }

    /// Listens to every trackpad connected now, so one connected since the last time counts too.
    func start() {
        guard devices == nil, let createList, let register, let startDevice,
              let list = createList()?.takeRetainedValue() else { return }
        Self.current = self
        devices = list
        forEachDevice { device in
            register(device, trackpadFrameCallback)
            startDevice(device, 0)
        }
    }

    func stop() {
        guard devices != nil else { return }
        forEachDevice { device in
            unregister?(device, trackpadFrameCallback)
            stopDevice?(device)
        }
        devices = nil
    }

    private func forEachDevice(_ body: (UnsafeMutableRawPointer) -> Void) {
        guard let devices else { return }
        for index in 0..<CFArrayGetCount(devices) {
            if let device = CFArrayGetValueAtIndex(devices, index) {
                body(UnsafeMutableRawPointer(mutating: device))
            }
        }
    }

    fileprivate func receive(_ frame: Frame) {
        guard isRunning else { return }
        onFrame?(frame)
    }
}

/// Reads one frame of MultitouchSupport's `MTTouch` records (96 bytes each): the state at byte
/// 20, where 3 is touching down and 4 touching, and the normalized position at 32 (x) and 36 (y).
/// Fingers merely near the trackpad have lower states, lifting ones higher.
private nonisolated func trackpadFrameCallback(
    device: UnsafeMutableRawPointer?,
    touches: UnsafeMutableRawPointer?,
    count: Int32,
    timestamp: Double,
    frame: Int32
) -> Int32 {
    var fingers = 0
    var sum = CGPoint.zero
    if let touches {
        for index in 0..<Int(max(count, 0)) {
            let touch = UnsafeRawPointer(touches) + index * 96
            let state = touch.load(fromByteOffset: 20, as: Int32.self)
            guard state == 3 || state == 4 else { continue }
            sum.x += CGFloat(touch.load(fromByteOffset: 32, as: Float.self))
            sum.y += CGFloat(touch.load(fromByteOffset: 36, as: Float.self))
            fingers += 1
        }
    }
    let frame = TrackpadTouches.Frame(
        count: fingers,
        center: fingers > 0 ? CGPoint(x: sum.x / CGFloat(fingers), y: sum.y / CGFloat(fingers)) : .zero
    )
    // Frames arrive on MultitouchSupport's own thread.
    DispatchQueue.main.async {
        MainActor.assumeIsolated { TrackpadTouches.current?.receive(frame) }
    }
    return 0
}
