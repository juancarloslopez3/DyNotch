import SwiftUI

/// The centerpiece of the Home tab: date, a large time and up to two world clocks.
struct ClockCard: View {
    @Environment(AppServices.self) private var services
    /// With about half the column, the world clocks make way.
    var height = HomeCardHeight.full

    var body: some View {
        let zones = services.settings.worldClockIDs.compactMap(TimeZone.init(identifier:))
        let opensSettings = !services.settings.headerSettingsButton
        GlassCard(padding: 10, isInteractive: opensSettings) {
            TimelineView(.everyMinute) { context in
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    Text(context.date, format: .dateTime.weekday(.wide).month(.abbreviated).day())
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(context.date, format: .dateTime.hour(.defaultDigits(amPM: .omitted)).minute())
                            .font(.system(size: 40, weight: .semibold, design: .rounded).monospacedDigit())
                            .contentTransition(.numericText())
                        if let period = Self.period(context.date) {
                            Text(period)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    if !zones.isEmpty, height != .half {
                        VStack(spacing: 2) {
                            ForEach(zones.prefix(2), id: \.identifier) { zone in
                                HStack {
                                    Text(Self.cityName(zone))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                    Spacer(minLength: 4)
                                    Text(Self.time(context.date, in: zone))
                                        .monospacedDigit()
                                }
                                .font(.system(size: 10.5, weight: .medium))
                            }
                        }
                        .padding(.top, 6)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .modifier(OpensSettings(isEnabled: opensSettings))
    }

    /// AM/PM, shown small beside the time, when the user's clock is 12-hour.
    static func period(_ date: Date) -> String? {
        let calendar = Calendar.current
        let symbol = calendar.component(.hour, from: date) < 12 ? calendar.amSymbol : calendar.pmSymbol
        return date.formatted(.dateTime.hour()).contains(symbol) ? symbol : nil
    }

    /// The zone's city in DyNotch's language ("Tokio" in Spanish), or the last part of its
    /// identifier for a zone without one, e.g. "GMT+3".
    static func cityName(_ zone: TimeZone) -> String {
        let fromIdentifier = (zone.identifier.split(separator: "/").last.map(String.init) ?? zone.identifier)
            .replacingOccurrences(of: "_", with: " ")
        guard zone.identifier.contains("/"), !zone.identifier.hasPrefix("Etc/") else { return fromIdentifier }
        cityFormatter.timeZone = zone
        return cityFormatter.string(from: .now)
    }

    /// "VVV" is the zone's exemplar city.
    private static let cityFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "VVV"
        return formatter
    }()

    static func time(_ date: Date, in zone: TimeZone) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.timeZone = zone
        return date.formatted(style)
    }
}

/// The time on one line, with the date beside it when there's room.
struct ClockSmallCard: View {
    @Environment(AppServices.self) private var services
    let isNarrow: Bool

    var body: some View {
        let opensSettings = !services.settings.headerSettingsButton
        SmallWidgetCard(isInteractive: opensSettings) {
            TimelineView(.everyMinute) { context in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(context.date, format: .dateTime.hour(.defaultDigits(amPM: .omitted)).minute())
                            .font(.system(size: 18, weight: .semibold, design: .rounded).monospacedDigit())
                            .contentTransition(.numericText())
                        if let period = ClockCard.period(context.date) {
                            Text(period)
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .fixedSize()
                    if !isNarrow {
                        Spacer(minLength: 0)
                        Text(context.date, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .minimumScaleFactor(0.85)
                            .layoutPriority(1)
                    }
                }
                .lineLimit(1)
                .help(context.date.formatted(date: .complete, time: .omitted))
            }
        }
        .modifier(OpensSettings(isEnabled: opensSettings))
    }
}

/// Without the settings button in the top bar, clicking the clock opens Settings.
private struct OpensSettings: ViewModifier {
    let isEnabled: Bool

    func body(content: Content) -> some View {
        content
            .gesture(TapGesture().onEnded { SettingsWindowController.shared.show() }, isEnabled: isEnabled)
            .accessibilityActions {
                if isEnabled {
                    Button("Open Settings") { SettingsWindowController.shared.show() }
                }
            }
            .help(isEnabled ? "Settings" : "")
    }
}
