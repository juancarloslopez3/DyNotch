import CoreLocation
import SwiftUI

/// The conditions now, the day's high and low, and the next hours. With about half the column
/// the hours have no room, so clicking the card turns it over to them.
struct WeatherCard: View {
    @Environment(AppServices.self) private var services
    /// With about half the column, the next hours move to the back.
    var height = HomeCardHeight.full

    var body: some View {
        let weather = services.weather
        Group {
            if let snapshot = weather.snapshot {
                let isHalf = height == .half
                FlipCard(canFlip: isHalf) {
                    GlassCard(padding: 10, isInteractive: isHalf) {
                        CurrentWeather(snapshot: snapshot, showsHours: !isHalf)
                    }
                } back: {
                    GlassCard(padding: 10, isInteractive: true) {
                        ComingWeather(snapshot: snapshot)
                    }
                }
            } else {
                GlassCard(padding: 10) {
                    WeatherPlaceholder(status: weather.status)
                }
            }
        }
        .modifier(WeatherUpdates())
    }

    static func degrees(_ value: Double) -> String {
        "\(Int(value.rounded()))°"
    }
}

/// The current conditions on one row: the symbol and temperature, with the conditions and
/// the day's high and low beside them when there's room. Clicking turns it over to the next
/// hours, or to the high and low when it's narrow.
struct WeatherSmallCard: View {
    @Environment(AppServices.self) private var services
    let isNarrow: Bool

    var body: some View {
        let weather = services.weather
        Group {
            if let snapshot = weather.snapshot {
                FlipCard {
                    SmallWidgetCard(isInteractive: true) {
                        CompactWeatherRow(snapshot: snapshot, isNarrow: isNarrow)
                    }
                } back: {
                    SmallWidgetCard(isInteractive: true) {
                        if isNarrow {
                            HighLow(snapshot: snapshot)
                        } else {
                            CompactHours(hours: snapshot.hourly)
                        }
                    }
                }
            } else {
                SmallWidgetCard {
                    WeatherPlaceholder(status: weather.status, isCompact: true, isNarrow: isNarrow)
                }
            }
        }
        .modifier(WeatherUpdates())
    }
}

/// The front of the large card: the conditions now and, with room for them, the next hours.
private struct CurrentWeather: View {
    let snapshot: WeatherSnapshot
    let showsHours: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center) {
                Image(systemName: snapshot.symbol)
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 22))
                Spacer(minLength: 0)
                Text(WeatherCard.degrees(snapshot.temperature))
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .contentTransition(.numericText(value: snapshot.temperature))
            }
            Text(snapshot.conditions)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
            Text("\(snapshot.locationName) · H:\(WeatherCard.degrees(snapshot.high))  L:\(WeatherCard.degrees(snapshot.low))")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            if showsHours {
                HoursRow(hours: Array(snapshot.hourly.prefix(3)))
            }
        }
    }
}

/// The back of a large card too short for the next hours: how warm it feels now, and as many
/// of the coming hours as fit side by side.
private struct ComingWeather: View {
    let snapshot: WeatherSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("Next Hours")
                    .font(.system(size: 11, weight: .semibold))
                Spacer(minLength: 4)
                Text("Feels like \(WeatherCard.degrees(snapshot.apparentTemperature))")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            Spacer(minLength: 0)
            ViewThatFits(in: .horizontal) {
                ForEach([5, 4, 3], id: \.self) { count in
                    HoursRow(hours: Array(snapshot.hourly.prefix(count)), spacing: 8)
                }
            }
        }
    }
}

/// Hours side by side, each its time over its conditions over its temperature.
private struct HoursRow: View {
    let hours: [HourlyForecast]
    var spacing: CGFloat = 0

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(hours) { hour in
                VStack(spacing: 2) {
                    Text(hour.time, format: .dateTime.hour(.defaultDigits(amPM: .narrow)))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                    Image(systemName: WeatherCodes.symbol(for: hour.code, isDay: hour.isDay))
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 11))
                        .frame(height: 13)
                    Text(WeatherCard.degrees(hour.temperature))
                        .font(.system(size: 10, weight: .semibold))
                }
                .fixedSize()
                .frame(maxWidth: .infinity)
            }
        }
    }
}

/// The back of a small card: the next hours on one row, each its time over its conditions and
/// temperature, as many as fit.
private struct CompactHours: View {
    let hours: [HourlyForecast]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            ForEach([5, 4, 3, 2, 1], id: \.self) { count in
                HStack(spacing: 10) {
                    ForEach(hours.prefix(count)) { hour in
                        VStack(spacing: 0) {
                            Text(hour.time, format: .dateTime.hour(.defaultDigits(amPM: .narrow)))
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.secondary)
                            HStack(spacing: 2) {
                                Image(systemName: WeatherCodes.symbol(for: hour.code, isDay: hour.isDay))
                                    .symbolRenderingMode(.multicolor)
                                    .font(.system(size: 10))
                                Text(WeatherCard.degrees(hour.temperature))
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                            }
                        }
                        .fixedSize()
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .lineLimit(1)
    }
}

/// The back of a narrow small card: the day's high over its low.
private struct HighLow: View {
    let snapshot: WeatherSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("H:\(WeatherCard.degrees(snapshot.high))")
            Text("L:\(WeatherCard.degrees(snapshot.low))")
                .foregroundStyle(.secondary)
        }
        .font(.system(size: 11, weight: .semibold, design: .rounded))
        .lineLimit(1)
    }
}

/// A first fetch for a widget switched on after launch (nothing is fetched while it's off).
private struct WeatherUpdates: ViewModifier {
    @Environment(AppServices.self) private var services

    func body(content: Content) -> some View {
        let weather = services.weather
        content
            .task {
                if weather.snapshot == nil, weather.status == .idle { await weather.refresh() }
            }
    }
}

private struct CompactWeatherRow: View {
    let snapshot: WeatherSnapshot
    var isNarrow = false

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: isNarrow ? 4 : 6) {
                Image(systemName: snapshot.symbol)
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: isNarrow ? 16 : 18))
                Text(WeatherCard.degrees(snapshot.temperature))
                    .font(.system(size: isNarrow ? 16 : 18, weight: .semibold, design: .rounded))
                    .contentTransition(.numericText(value: snapshot.temperature))
            }
            .fixedSize()
            if !isNarrow {
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 1) {
                    Text(snapshot.conditions)
                        .font(.system(size: 10.5, weight: .semibold))
                        .minimumScaleFactor(0.85)
                    Text("H:\(WeatherCard.degrees(snapshot.high))  L:\(WeatherCard.degrees(snapshot.low))")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                }
                // Served before the spacer, which would otherwise cut it short with room to spare.
                .layoutPriority(1)
            }
        }
        .lineLimit(1)
    }
}

private struct WeatherPlaceholder: View {
    @Environment(AppServices.self) private var services
    let status: WeatherService.Status
    /// On one row, in a small widget.
    var isCompact = false
    /// Buttons only.
    var isNarrow = false

    var body: some View {
        let layout = isCompact ? AnyLayout(HStackLayout(spacing: 6)) : AnyLayout(VStackLayout(spacing: 6))
        layout {
            switch status {
            case .loading, .idle:
                ProgressView().controlSize(.small)
            case .needsLocation:
                if !isNarrow {
                    Text(isCompact ? "No location" : "Weather needs your location or a city")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(isCompact ? 1 : nil)
                }
                HStack(spacing: 6) {
                    Button {
                        if services.weather.location.authorizationStatus == .denied {
                            services.permissions.openSettings(.location)
                        } else {
                            Task { await services.weather.requestLocationAccess() }
                        }
                    } label: {
                        Image(systemName: "location.fill")
                    }
                    .help("Use My Location")
                    if !isNarrow {
                        Button {
                            SettingsWindowController.shared.show(pane: .weather)
                        } label: {
                            Image(systemName: "magnifyingglass")
                        }
                        .help("Choose a City")
                    }
                }
                .buttonStyle(.glass)
                .controlSize(.small)
            case .failed:
                if !isNarrow {
                    Image(systemName: "wifi.exclamationmark")
                        .foregroundStyle(.secondary)
                }
                Button("Retry") {
                    Task { await services.weather.refresh() }
                }
                .buttonStyle(.glass)
                .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
