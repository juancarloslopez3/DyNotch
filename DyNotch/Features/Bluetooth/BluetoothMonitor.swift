import CoreBluetooth
import Foundation
import IOBluetooth
import IOKit
import OSLog
import SwiftUI

nonisolated struct BluetoothBattery: Equatable, Sendable {
    var main: Int?
    var left: Int?
    var right: Int?
    var caseLevel: Int?

    var isEmpty: Bool { main == nil && left == nil && right == nil }
    /// The level to show in a single ring (the lower bud for AirPods).
    var summary: Int? { [left, right].compactMap { $0 }.min() ?? main }
}

struct BluetoothEvent: Equatable {
    var address: String
    var name: String
    var symbol: String
    var isConnected: Bool
    var battery: BluetoothBattery?
    /// Set for AirPods, which connect with an animation of their own.
    var airPods: AirPodsModel? = nil
    /// Apple's product and color IDs, where the device gives them, for its picture.
    var productID: Int? = nil
    var colorID: Int? = nil
    /// Off in Settings, AirPods show up beside the notch like any other device.
    var animatesAirPods = true

    /// The AirPods to play the connect animation for, if any.
    var animatedAirPods: AirPodsModel? { isConnected && animatesAirPods ? airPods : nil }
}

/// The AirPods (and Beats) DyNotch animates when they connect.
nonisolated enum AirPodsModel: Equatable, Sendable {
    /// 1st and 2nd generation.
    case airPods
    case airPods3
    case airPods4
    case airPodsPro
    case airPodsMax
    /// Beats headphones, earbuds and speakers, which turn into view like AirPods.
    case beats(productID: Int)

    /// From the Bluetooth product ID (vendor 0x004C), so AirPods that were renamed are still known.
    init?(productID: Int) {
        switch productID {
        case 0x2002, 0x200F: self = .airPods
        case 0x2013: self = .airPods3
        case 0x2019, 0x201B: self = .airPods4
        case 0x200E, 0x2014, 0x2024, 0x2027: self = .airPodsPro
        case 0x200A, 0x201F, 0x202D: self = .airPodsMax
        default:
            guard Self.beats[productID] != nil else { return nil }
            self = .beats(productID: productID)
        }
    }

    /// Each Beats model's name, for where theirs doesn't fit, and symbol.
    static let beats: [Int: (name: String, symbol: String)] = [
        0x2003: ("Powerbeats³", "beats.powerbeats3"),
        0x2005: ("Beatsˣ", "beats.earphones"),
        0x2006: ("Beats Solo³", "beats.headphones"),
        0x2007: ("Beats Studio³", "beats.headphones"),
        0x2009: ("Beats Studio³", "beats.headphones"),
        0x200B: ("Powerbeats Pro", "beats.powerbeats.pro"),
        0x200C: ("Beats Solo Pro", "beats.headphones"),
        0x200D: ("Powerbeats", "beats.powerbeats"),
        0x2010: ("Beats Flex", "beats.earphones"),
        0x2011: ("Beats Studio Buds", "beats.studiobuds"),
        0x2012: ("Beats Fit Pro", "beats.fitpro"),
        0x2016: ("Beats Studio Buds +", "beats.studiobuds.plus"),
        0x2017: ("Beats Studio Pro", "beats.headphones"),
        0x201A: ("Beats Pill", "beats.pill.fill"),
        0x201D: ("Powerbeats Pro 2", "beats.powerbeats.pro.2"),
        0x2025: ("Beats Solo⁴", "beats.headphones"),
        0x2026: ("Beats Solo Buds", "beats.solobuds"),
        0x202F: ("Beats Fit Pro", "beats.fitpro"),
        0x2038: ("Beats", "beats.headphones"),
    ]

    /// From the name macOS gave them ("AirPods Max de Carlos", "Jane’s AirPods Pro").
    init?(name: String) {
        let lower = name.lowercased()
        if lower.contains("airpods max") {
            self = .airPodsMax
        } else if lower.contains("airpods pro") {
            self = .airPodsPro
        } else if lower.contains("airpods 4") {
            self = .airPods4
        } else if lower.contains("airpods") {
            self = .airPods
        } else {
            return nil
        }
    }

    var name: String {
        switch self {
        case .airPods, .airPods3: "AirPods"
        case .airPods4: "AirPods 4"
        case .airPodsPro: "AirPods Pro"
        case .airPodsMax: "AirPods Max"
        case .beats(let productID): Self.beats[productID]?.name ?? "Beats"
        }
    }

    /// One of the model's product IDs, for its picture when the AirPods didn't give theirs.
    var typicalProductID: Int {
        switch self {
        case .airPods: 0x200F
        case .airPods3: 0x2013
        case .airPods4: 0x2019
        case .airPodsPro: 0x2024
        case .airPodsMax: 0x201F
        case .beats(let productID): productID
        }
    }

    /// Its turn rendered from a 3D model, where the app has one (`<name>.turntable.heic`), in the
    /// AirPods' color: by the color ID they report, as CoreBluetoothUI pictures them, else in the
    /// one macOS shows when it doesn't know (Space Gray for the first AirPods Max, Starlight after).
    /// AirPods Pro only come in white.
    func turntable(productID: Int, colorID: Int?) -> String? {
        if self == .airPodsPro { return "AirPodsPro" }
        guard self == .airPodsMax else { return nil }
        let color: String? = switch colorID ?? -1 {
        case 0x00, 0x0F: "SpaceGray"
        case 0x10: "Silver"
        case 0x11: "Green"
        case 0x03: "SkyBlue"
        case 0x02: "Pink"
        case 0x12: "Midnight"
        case 0x13: "Starlight"
        case 0x14: "Blue"
        case 0x15: "Orange"
        case 0x16: "Purple"
        default: nil
        }
        return "AirPodsMax-" + (color ?? (productID == 0x200A ? "SpaceGray" : "Starlight"))
    }

    /// The pair, or the headphones.
    var symbol: String {
        switch self {
        case .airPods: "airpods"
        case .airPods3: "airpods.gen3"
        case .airPods4: "airpods.gen4"
        case .airPodsPro: "airpods.pro"
        case .airPodsMax: "airpods.max"
        case .beats(let productID): Self.beats[productID]?.symbol ?? "beats.headphones"
        }
    }
}

/// Posts a live activity when a Bluetooth device connects or disconnects, with its
/// battery level where macOS knows it.
final class BluetoothMonitor: NSObject {
    private static let logger = Logger(subsystem: "app.dynotch", category: "Bluetooth")
    private weak var services: AppServices?
    private var connectNotification: IOBluetoothUserNotification?
    private var startedAt = Date.now

    /// Starts only once Bluetooth access was granted, so launching never triggers a prompt.
    func startIfAuthorized(services: AppServices) {
        self.services = services
        guard connectNotification == nil, CBManager.authorization == .allowedAlways else { return }
        startedAt = .now
        connectNotification = IOBluetoothDevice.register(forConnectNotifications: self, selector: #selector(deviceConnected(_:device:)))
        // Apple's pictures of the AirPods and Beats paired with this Mac, ready for when they connect.
        if services.settings.liveBluetooth, services.settings.liveAirPodsAnimation {
            for case let device as IOBluetoothDevice in IOBluetoothDevice.pairedDevices() ?? [] {
                guard let productID = Self.appleProductID(device) else { continue }
                DeviceArt.shared.prepare(productID: productID, colorID: Self.privateValue(device, "colorID"))
            }
        }
    }

    // IOBluetooth calls these on its own queue (macOS 27), not the main thread.
    @objc private nonisolated func deviceConnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        nonisolated(unsafe) let device = device
        DispatchQueue.main.async {
            MainActor.assumeIsolated { self.connected(device) }
        }
    }

    @objc private nonisolated func deviceDisconnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        notification.unregister()
        nonisolated(unsafe) let device = device
        DispatchQueue.main.async {
            MainActor.assumeIsolated { self.post(device, connected: false) }
        }
    }

    private func connected(_ device: IOBluetoothDevice) {
        device.register(forDisconnectNotification: self, selector: #selector(deviceDisconnected(_:device:)))
        // Registration replays already-connected devices; ignore that initial burst.
        guard Date.now.timeIntervalSince(startedAt) > 3 else { return }
        post(device, connected: true)
    }

    private func post(_ device: IOBluetoothDevice, connected: Bool) {
        guard let services, services.settings.liveBluetooth else { return }
        Self.logger.notice("\(connected ? "Connected" : "Disconnected", privacy: .public) \(device.name == nil ? "unnamed" : "named", privacy: .public) device, class \(device.deviceClassMajor)/\(device.deviceClassMinor), LE \(Self.privateValue(device, "isLowEnergyConnection") ?? -1), product \(Self.privateValue(device, "productID") ?? -1), color \(Self.privateValue(device, "colorID") ?? -1)")
        // macOS names every accessory. A link without a name is an iPhone (iPad, Watch) reaching
        // the Mac over Bluetooth LE for a second, for Handoff and the like, many times an hour.
        guard let name = device.name, !name.isEmpty else { return }
        guard services.settings.liveBluetoothContinuity
            || !Self.isPhoneTabletOrWatch(name: name, major: device.deviceClassMajor, minor: device.deviceClassMinor)
        else { return }
        let productID = Self.appleProductID(device)
        let airPods = productID.flatMap(AirPodsModel.init(productID:)) ?? AirPodsModel(name: name)
        let colorID = productID == nil ? nil : Self.privateValue(device, "colorID")
        // AirPods or Beats without Apple's model here yet (paired since DyNotch started, or in
        // another color) show once it's in, so they turn in 3D from the start: ~1.5 s, once.
        guard connected, airPods != nil, services.settings.liveAirPodsAnimation, let productID,
              DeviceArt.shared.prepare(productID: productID, colorID: colorID) != nil
        else {
            show(device, name: name, airPods: airPods, productID: productID, colorID: colorID, connected: connected)
            return
        }
        Task {
            await DeviceArt.shared.ready(productID: productID, colorID: colorID, within: .seconds(5))
            // Gone again meanwhile: that already showed.
            guard device.isConnected() else { return }
            show(device, name: name, airPods: airPods, productID: productID, colorID: colorID, connected: connected)
        }
    }

    private func show(_ device: IOBluetoothDevice, name: String, airPods: AirPodsModel?, productID: Int?, colorID: Int?, connected: Bool) {
        guard let services else { return }
        let address = Self.normalize(device.addressString ?? "")
        let event = BluetoothEvent(
            address: address,
            name: name,
            symbol: airPods?.symbol ?? Self.symbol(name: name, major: device.deviceClassMajor, minor: device.deviceClassMinor),
            isConnected: connected,
            battery: connected ? Self.hidBattery(address: address) ?? Self.deviceBattery(device) : nil,
            airPods: airPods,
            productID: productID,
            colorID: colorID,
            animatesAirPods: services.settings.liveAirPodsAnimation
        )
        let id = "bt-\(address)"
        // AirPods stay a little longer, for their animation and then their battery.
        let duration = connected && airPods != nil ? 5.0 : 3.5
        services.activities.post(LiveActivity(id: id, kind: .bluetooth(event), duration: duration))

        // AirPods report their battery a moment after connecting. IOBluetooth's own copy is
        // cheap to look at; system_profiler is slow but always knows, so ask it now and then.
        guard connected, event.battery == nil else { return }
        Task {
            for attempt in 1...8 {
                try? await Task.sleep(for: .seconds(0.4))
                var battery = Self.deviceBattery(device)
                if battery == nil, attempt.isMultiple(of: 4) {
                    battery = await Self.systemProfilerBattery(address: address)
                }
                if let battery {
                    services.activities.update(id: id) { activity in
                        if case .bluetooth(var updated) = activity.kind {
                            updated.battery = battery
                            activity.kind = .bluetooth(updated)
                        }
                    }
                    return
                }
            }
        }
    }

    // MARK: - AirPods

    /// The product ID of an Apple (or Beats) accessory. `productID` and `vendorID` are private
    /// getters, so this checks they're there before asking.
    static func appleProductID(_ device: IOBluetoothDevice) -> Int? {
        privateValue(device, "vendorID") == 0x004C ? privateValue(device, "productID") : nil
    }

    private static func privateValue(_ device: IOBluetoothDevice, _ key: String) -> Int? {
        guard device.responds(to: NSSelectorFromString(key)) else { return nil }
        return device.value(forKey: key) as? Int
    }

    // MARK: - Battery sources

    /// Magic Keyboard / Mouse / Trackpad expose `BatteryPercent` in the IORegistry.
    static func hidBattery(address: String) -> BluetoothBattery? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleDeviceManagementHIDEventService"), &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            guard let deviceAddress = IORegistryEntryCreateCFProperty(service, "DeviceAddress" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? String,
                normalize(deviceAddress) == address,
                let percent = IORegistryEntryCreateCFProperty(service, "BatteryPercent" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? Int
            else { continue }
            return BluetoothBattery(main: percent)
        }
        return nil
    }

    /// AirPods and Beats battery as IOBluetooth keeps it (private getters; anything outside 1–100 counts as not known).
    static func deviceBattery(_ device: IOBluetoothDevice) -> BluetoothBattery? {
        func level(_ key: String) -> Int? {
            privateValue(device, key).flatMap { (1...100).contains($0) ? $0 : nil }
        }
        let battery = BluetoothBattery(
            main: level("batteryPercentSingle"),
            left: level("batteryPercentLeft"),
            right: level("batteryPercentRight"),
            caseLevel: level("batteryPercentCase")
        )
        return battery.isEmpty ? nil : battery
    }

    /// AirPods and Beats battery (left / right / case) from `system_profiler`.
    nonisolated static func systemProfilerBattery(address: String) async -> BluetoothBattery? {
        await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
            process.arguments = ["SPBluetoothDataType", "-json"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            guard (try? process.run()) != nil else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return parseSystemProfiler(data, address: address)
        }.value
    }

    nonisolated static func parseSystemProfiler(_ data: Data, address: String) -> BluetoothBattery? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sections = root["SPBluetoothDataType"] as? [[String: Any]]
        else { return nil }
        for section in sections {
            for entry in section["device_connected"] as? [[String: Any]] ?? [] {
                for case let properties as [String: Any] in entry.values {
                    guard normalize(properties["device_address"] as? String ?? "") == address else { continue }
                    func level(_ key: String) -> Int? {
                        (properties[key] as? String).flatMap { Int($0.filter(\.isNumber)) }
                    }
                    let battery = BluetoothBattery(
                        main: level("device_batteryLevelMain"),
                        left: level("device_batteryLevelLeft"),
                        right: level("device_batteryLevelRight"),
                        caseLevel: level("device_batteryLevelCase")
                    )
                    return battery.isEmpty ? nil : battery
                }
            }
        }
        return nil
    }

    nonisolated static func normalize(_ address: String) -> String {
        address.uppercased().filter(\.isHexDigit)
    }

    /// iPhones, iPads and Apple Watches, which connect by themselves now and then (Handoff,
    /// unlocking the Mac): a phone, a tablet or a wristwatch by device class, else by name, as
    /// ones on Bluetooth LE have no class ("iPhone de Carlos", "Jane’s Apple Watch").
    static func isPhoneTabletOrWatch(name: String, major: BluetoothDeviceClassMajor, minor: BluetoothDeviceClassMinor) -> Bool {
        phoneTabletOrWatchSymbol(name: name, major: major, minor: minor) != nil
    }

    /// The symbol of an iPhone, iPad or Apple Watch (any other phone's too), nil for anything else.
    static func phoneTabletOrWatchSymbol(name: String, major: BluetoothDeviceClassMajor, minor: BluetoothDeviceClassMinor) -> String? {
        // macOS names a watch with a non-breaking space: "Apple\u{A0}Watch".
        let lower = name.lowercased().replacingOccurrences(of: "\u{A0}", with: " ")
        if lower.contains("iphone") { return "iphone" }
        if lower.contains("ipad") || (major == 0x01 && minor == 0x07) { return "ipad" }
        if lower.contains("apple watch") || (major == 0x07 && minor == 0x01) { return "applewatch" }
        return major == 0x02 ? "smartphone" : nil
    }

    static func symbol(name: String, major: BluetoothDeviceClassMajor, minor: BluetoothDeviceClassMinor) -> String {
        let lower = name.lowercased()
        if lower.contains("airpods max") { return "airpods.max" }
        if lower.contains("airpods pro") { return "airpods.pro" }
        if lower.contains("airpods") { return "airpods" }
        if lower.contains("beats") { return "beats.headphones" }
        if lower.contains("mouse") { return "magicmouse.fill" }
        if lower.contains("trackpad") { return "rectangle.and.hand.point.up.left.filled" }
        if lower.contains("keyboard") { return "keyboard.fill" }
        if lower.contains("controller") || lower.contains("dualsense") || lower.contains("xbox") { return "gamecontroller.fill" }
        if let symbol = phoneTabletOrWatchSymbol(name: name, major: major, minor: minor) { return symbol }
        switch major {
        case 0x04: return "headphones"
        case 0x05: return minor & 0x10 != 0 ? "keyboard.fill" : "magicmouse.fill"
        default: return "dot.radiowaves.left.and.right"
        }
    }
}

struct BluetoothActivityView: View {
    let event: BluetoothEvent
    let notch: CGSize

    var body: some View {
        WingsLayout(notch: notch) {
            HStack(spacing: 7) {
                Image(systemName: event.symbol)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(event.isConnected ? .white : .white.opacity(0.45))
                // AirPods fall back to their model's name where theirs doesn't fit.
                ViewThatFits(in: .horizontal) {
                    Text(event.name)
                    Text(event.airPods?.name ?? event.name)
                }
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.tail)
            }
            .padding(.horizontal, 10)
        } trailing: {
            if !event.isConnected {
                Text("Disconnected")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
            } else if let level = event.battery?.summary {
                BatteryGauge(level: level, ring: 14, spacing: 6)
                    .transition(.blurReplace)
            } else {
                Text("Connected")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.green)
            }
        }
        .animation(.notchQuick, value: event)
    }
}
