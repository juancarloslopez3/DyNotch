import Foundation

/// WMO weather interpretation codes (as used by Open-Meteo) mapped to SF Symbols.
nonisolated enum WeatherCodes {
    static func symbol(for code: Int, isDay: Bool) -> String {
        switch code {
        case 0: isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2: isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: "cloud.fill"
        case 45, 48: "cloud.fog.fill"
        case 51, 53, 55: "cloud.drizzle.fill"
        case 56, 57, 66, 67: "cloud.sleet.fill"
        case 61, 63: "cloud.rain.fill"
        case 65: "cloud.heavyrain.fill"
        case 71, 73, 75, 77, 85, 86: "cloud.snow.fill"
        case 80, 81: isDay ? "cloud.sun.rain.fill" : "cloud.moon.rain.fill"
        case 82: "cloud.heavyrain.fill"
        case 95, 96, 99: "cloud.bolt.rain.fill"
        default: "cloud.fill"
        }
    }

    static func description(for code: Int) -> String {
        switch code {
        // Its own key: "Clear" is also the Shelf's button.
        case 0: String(localized: "weather.clear", defaultValue: "Clear", comment: "Weather conditions: a clear sky")
        case 1: String(localized: "Mostly Clear")
        case 2: String(localized: "Partly Cloudy")
        case 3: String(localized: "Cloudy")
        case 45, 48: String(localized: "Fog")
        case 51, 53, 55: String(localized: "Drizzle")
        case 56, 57: String(localized: "Freezing Drizzle")
        case 61: String(localized: "Light Rain")
        case 63: String(localized: "Rain")
        case 65: String(localized: "Heavy Rain")
        case 66, 67: String(localized: "Freezing Rain")
        case 71: String(localized: "Light Snow")
        case 73: String(localized: "Snow")
        case 75: String(localized: "Heavy Snow")
        case 77: String(localized: "Snow Grains")
        case 80, 81: String(localized: "Showers")
        case 82: String(localized: "Heavy Showers")
        case 85, 86: String(localized: "Snow Showers")
        case 95: String(localized: "Thunderstorm")
        case 96, 99: String(localized: "Thunderstorm with Hail")
        default: String(localized: "Unknown")
        }
    }
}
