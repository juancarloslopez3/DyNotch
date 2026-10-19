import CoreBluetooth
import Foundation
import IOBluetooth
import IOKit
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
    /// Set for AirPods, which drop down with their own animation when they connect.
    var airPods: AirPodsModel? = nil
    /// Off in Settings, AirPods show up beside the notch like any other device.
    var animatesAirPods = true

    /// The AirPods to play the connect animation for, if any.
    var animatedAirPods: AirPodsModel? { isConnected && animatesAirPods ? airPods : nil }
}

/// The AirPods DyNotch animates when they connect.
nonisolated enum AirPodsModel: Equatable, Sendable {
    /// 1st and 2nd generation.
    case airPods
    case airPods3
    case airPods4
    case airPodsPro
    case airPodsMax

    /// From the Bluetooth product ID (vendor 0x004C), so AirPods that were renamed are still known.
    init?(productID: Int) {
        switch productID {
        case 0x2002, 0x200F: self = .airPods
        case 0x2013: self = .airPods3
        case 0x2019, 0x201B: self = .airPods4
        case 0x200E, 0x2014, 0x2024: self = .airPodsPro
        case 0x200A, 0x201F: self = .airPodsMax
        default: return nil
        }
    }

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
        }
    }

    /// The pair, or the headphones.
    var symbol: String {
        switch self {
        case .airPods: "airpods"
        case .airPods3: "airpods.gen3"
        case .airPods4: "airpods.gen4"
        case .airPodsPro: "airpods.pro"
        case .airPodsMax: "airpods.max"
        }
    }

    /// Each bud and the case they come out of; nil for the over-ear AirPods Max.
    var earbuds: (left: String, right: String, chargingCase: String)? {
        switch self {
        case .airPods: ("airpod.left", "airpod.right", "airpods.chargingcase.fill")
        case .airPods3: ("airpod.gen3.left", "airpod.gen3.right", "airpods.gen3.chargingcase.wireless.fill")
        // The 4th generation buds have no symbols of their own; they look like the 3rd's.
        case .airPods4: ("airpod.gen3.left", "airpod.gen3.right", "airpods.gen4.chargingcase.wireless.fill")
        case .airPodsPro: ("airpodpro.left", "airpodpro.right", "airpods.pro.chargingcase.wireless.fill")
        case .airPodsMax: nil
        }
    }
}

/// Posts a live activity when a Bluetooth device connects or disconnects, with its
/// battery level where macOS knows it.
final class BluetoothMonitor: NSObject {
    private weak var services: AppServices?
    private var connectNotification: IOBluetoothUserNotification?
    private var startedAt = Date.now

    /// Starts only once Bluetooth access was granted, so launching never triggers a prompt.
    func startIfAuthorized(services: AppServices) {
        self.services = services
        guard connectNotification == nil, CBManager.authorization == .allowedAlways else { return }
        startedAt = .now
        connectNotification = IOBluetoothDevice.register(forConnectNotifications: self, selector: #selector(deviceConnected(_:device:)))
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
        let address = Self.normalize(device.addressString ?? "")
        let name = device.name ?? String(localized: "Bluetooth Device")
        let airPods = Self.airPodsModel(device, name: name)
        let event = BluetoothEvent(
            address: address,
            name: name,
            symbol: airPods?.symbol ?? Self.symbol(name: name, major: device.deviceClassMajor, minor: device.deviceClassMinor),
            isConnected: connected,
            battery: connected ? Self.hidBattery(address: address) ?? Self.deviceBattery(device) : nil,
            airPods: airPods,
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

    /// From the device's product ID, else its name. `productID` and `vendorID` are private
    /// getters, so this checks they're there before asking.
    static func airPodsModel(_ device: IOBluetoothDevice, name: String) -> AirPodsModel? {
        if privateValue(device, "vendorID") == 0x004C, let productID = privateValue(device, "productID"),
           let model = AirPodsModel(productID: productID) {
            return model
        }
        return AirPodsModel(name: name)
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
                HStack(spacing: 6) {
                    ProgressRing(progress: Double(level) / 100, color: level <= 20 ? .orange : .green, lineWidth: 2.5)
                        .frame(width: 14, height: 14)
                    Text("\(level)%")
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                }
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
