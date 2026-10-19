import Foundation
import IOKit.ps
import Observation
import SwiftUI

struct BatteryEvent: Equatable {
    enum Kind: Equatable {
        case pluggedIn, unplugged, low, full
    }
    var kind: Kind
    var percent: Int
    var isCharging: Bool
    /// Minutes to full when charging, minutes left when on battery.
    var minutes: Int?
}

nonisolated struct BatteryReading: Equatable, Sendable {
    var percent: Int
    var isOnAC: Bool
    var isCharging: Bool
    var isCharged: Bool
    var minutesToFull: Int?
    var minutesToEmpty: Int?

    /// Reads the internal battery from IOKit. `nil` on Macs without one.
    static func current() -> BatteryReading? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType
            else { continue }
            let current = description[kIOPSCurrentCapacityKey] as? Int ?? 0
            let max = description[kIOPSMaxCapacityKey] as? Int ?? 100
            let toFull = description[kIOPSTimeToFullChargeKey] as? Int ?? -1
            let toEmpty = description[kIOPSTimeToEmptyKey] as? Int ?? -1
            return BatteryReading(
                percent: max > 0 ? Int((Double(current) / Double(max) * 100).rounded()) : current,
                isOnAC: description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue,
                isCharging: description[kIOPSIsChargingKey] as? Bool ?? false,
                isCharged: description[kIOPSIsChargedKey] as? Bool ?? false,
                minutesToFull: toFull > 0 ? toFull : nil,
                minutesToEmpty: toEmpty > 0 ? toEmpty : nil
            )
        }
        return nil
    }
}

/// Watches the battery and posts plug/unplug, low and full events.
@Observable
final class BatteryMonitor {
    private(set) var reading: BatteryReading?

    @ObservationIgnored private weak var services: AppServices?
    @ObservationIgnored private var runLoopSource: CFRunLoopSource?
    @ObservationIgnored private var warnedLevels: Set<Int> = []
    @ObservationIgnored private var announcedFull = false

    static let lowLevels = [20, 10]

    func start(services: AppServices) {
        self.services = services
        reading = BatteryReading.current()
        announcedFull = reading?.isCharged ?? false
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource(batteryCallback, context)?.takeRetainedValue() else { return }
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
    }

    fileprivate func powerSourceChanged() {
        guard let new = BatteryReading.current() else { return }
        let old = reading
        reading = new
        guard let old, let services, services.settings.liveBattery else { return }

        if new.isOnAC != old.isOnAC {
            warnedLevels = []
            announcedFull = new.isCharged
            post(BatteryEvent(
                kind: new.isOnAC ? .pluggedIn : .unplugged,
                percent: new.percent,
                isCharging: new.isCharging,
                minutes: new.isOnAC ? new.minutesToFull : new.minutesToEmpty
            ))
            return
        }
        if !new.isOnAC, let level = Self.lowLevels.first(where: { new.percent <= $0 && !warnedLevels.contains($0) }) {
            warnedLevels.formUnion(Self.lowLevels.filter { $0 >= level })
            post(BatteryEvent(kind: .low, percent: new.percent, isCharging: false, minutes: new.minutesToEmpty))
        }
        if new.isOnAC, !announcedFull, new.isCharged || new.percent >= 100 {
            announcedFull = true
            post(BatteryEvent(kind: .full, percent: new.percent, isCharging: false, minutes: nil))
        }
    }

    private func post(_ event: BatteryEvent) {
        services?.activities.post(LiveActivity(id: "battery", kind: .battery(event), duration: event.kind == .low ? 5 : 3))
    }
}

private nonisolated func batteryCallback(_ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    let monitor = Unmanaged<BatteryMonitor>.fromOpaque(context).takeUnretainedValue()
    // Delivered on the main run loop where the source was added.
    MainActor.assumeIsolated { monitor.powerSourceChanged() }
}

enum BatterySymbol {
    static func name(percent: Int, charging: Bool) -> String {
        if charging { return "battery.100percent.bolt" }
        return switch percent {
        case ..<13: "battery.0percent"
        case ..<38: "battery.25percent"
        case ..<63: "battery.50percent"
        case ..<88: "battery.75percent"
        default: "battery.100percent"
        }
    }

    static func color(percent: Int, charging: Bool) -> Color {
        if charging { return .green }
        return percent <= 10 ? .red : percent <= 20 ? .orange : .white
    }
}

struct BatteryActivityView: View {
    let event: BatteryEvent
    let notch: CGSize

    var body: some View {
        let charging = event.kind == .pluggedIn || event.isCharging
        let color: Color = switch event.kind {
        case .pluggedIn, .full: .green
        case .low: event.percent <= 10 ? .red : .orange
        case .unplugged: .white
        }
        WingsLayout(notch: notch) {
            HStack(spacing: 6) {
                Image(systemName: event.kind == .pluggedIn ? "bolt.fill" : event.kind == .low ? "exclamationmark.triangle.fill" : "powerplug.fill")
                    .foregroundStyle(color)
                    .symbolEffect(.bounce, value: event)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
            }
            .font(.system(size: 13, weight: .semibold))
        } trailing: {
            HStack(spacing: 6) {
                Text("\(event.percent)%")
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(color)
                Image(systemName: BatterySymbol.name(percent: event.percent, charging: charging))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(color, .white.opacity(0.5))
                    .font(.system(size: 15))
            }
        }
    }

    private var title: String {
        switch event.kind {
        case .pluggedIn: String(localized: "Charging")
        case .unplugged: String(localized: "On Battery")
        case .low: String(localized: "Low Battery")
        case .full: String(localized: "Charged")
        }
    }
}
