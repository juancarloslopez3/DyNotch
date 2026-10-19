import SwiftUI

/// The battery level in large type, with whether it's charging or how long it has left. With
/// about half the column, the symbol sits beside the rest.
struct BatteryCard: View {
    @Environment(AppServices.self) private var services
    var height = HomeCardHeight.full

    var body: some View {
        let isHalf = height == .half
        GlassCard(padding: 10) {
            Group {
                if let battery = services.battery.reading {
                    let layout = isHalf ? AnyLayout(HStackLayout(spacing: 10)) : AnyLayout(VStackLayout(spacing: 6))
                    layout {
                        Image(systemName: BatterySymbol.name(percent: battery.percent, charging: battery.isCharging))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(BatterySymbol.color(percent: battery.percent, charging: battery.isCharging), .white.opacity(0.45))
                            .font(.system(size: isHalf ? 24 : 30))
                        VStack(alignment: isHalf ? .leading : .center, spacing: 1) {
                            Text("\(battery.percent)%")
                                .font(.system(size: isHalf ? 24 : 30, weight: .semibold, design: .rounded).monospacedDigit())
                                .contentTransition(.numericText(value: Double(battery.percent)))
                            Text(BatterySmallCard.status(battery))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                } else {
                    SmallEmptyState(symbol: "powerplug.fill", text: "No battery", isNarrow: false)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// The battery level, and when there's room whether it's charging or how long it has left.
struct BatterySmallCard: View {
    @Environment(AppServices.self) private var services
    let isNarrow: Bool

    var body: some View {
        SmallWidgetCard {
            if let battery = services.battery.reading {
                let color = BatterySymbol.color(percent: battery.percent, charging: battery.isCharging)
                HStack(spacing: 6) {
                    HStack(spacing: isNarrow ? 4 : 6) {
                        Image(systemName: BatterySymbol.name(percent: battery.percent, charging: battery.isCharging))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(color, .white.opacity(0.45))
                            .font(.system(size: isNarrow ? 13 : 16))
                        Text("\(battery.percent)%")
                            .font(.system(size: isNarrow ? 14 : 16, weight: .semibold, design: .rounded).monospacedDigit())
                            .contentTransition(.numericText(value: Double(battery.percent)))
                    }
                    .fixedSize()
                    if !isNarrow {
                        Spacer(minLength: 0)
                        Text(Self.status(battery))
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(.secondary)
                            .minimumScaleFactor(0.85)
                            .layoutPriority(1)
                    }
                }
                .lineLimit(1)
                .help(Self.status(battery))
            } else {
                SmallEmptyState(symbol: "powerplug.fill", text: "No battery", isNarrow: isNarrow)
            }
        }
    }

    /// "48m to full", "Charged", "5h 12m left"…
    static func status(_ battery: BatteryReading) -> String {
        if battery.isCharging {
            return battery.minutesToFull.map { String(localized: "\(duration($0)) to full") } ?? String(localized: "Charging")
        }
        if battery.isOnAC {
            return battery.isCharged ? String(localized: "Charged") : String(localized: "Plugged in")
        }
        return battery.minutesToEmpty.map { String(localized: "\(duration($0)) left") } ?? String(localized: "On battery")
    }

    private static func duration(_ minutes: Int) -> String {
        Duration.seconds(minutes * 60).formatted(.units(allowed: [.hours, .minutes], width: .narrow))
    }
}
