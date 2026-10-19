import Foundation
import Testing

@testable import DyNotch

struct WeatherTests {
    @Test func codesMapToDayAndNightSymbols() {
        #expect(WeatherCodes.symbol(for: 0, isDay: true) == "sun.max.fill")
        #expect(WeatherCodes.symbol(for: 0, isDay: false) == "moon.stars.fill")
        #expect(WeatherCodes.symbol(for: 63, isDay: true) == "cloud.rain.fill")
        #expect(WeatherCodes.symbol(for: 95, isDay: false) == "cloud.bolt.rain.fill")
        // In DyNotch's language, which follows the Mac's.
        #expect(WeatherCodes.description(for: 3) == String(localized: "Cloudy"))
    }

    @Test func parsesForecastAndKeepsOnlyUpcomingHours() throws {
        let json = """
        {
          "current": {"temperature_2m": 14.6, "apparent_temperature": 12.1, "weather_code": 2, "is_day": 1},
          "hourly": {
            "time": [1000, 4600, 8200, 11800],
            "temperature_2m": [10, 11, 12, 13],
            "weather_code": [0, 1, 2, 3],
            "is_day": [1, 1, 1, 0]
          },
          "daily": {"temperature_2m_max": [18.2], "temperature_2m_min": [9.4]}
        }
        """
        let snapshot = try OpenMeteoClient.parse(
            Data(json.utf8), locationName: "Copenhagen", fahrenheit: false, now: Date(timeIntervalSince1970: 5000)
        )
        #expect(snapshot.temperature == 14.6)
        #expect(snapshot.high == 18.2)
        #expect(snapshot.low == 9.4)
        #expect(snapshot.symbol == "cloud.sun.fill")
        #expect(snapshot.hourly.map(\.temperature) == [12, 13])
        #expect(snapshot.hourly.last?.isDay == false)
    }

    @Test func forecastURLRequestsUnits() {
        let url = OpenMeteoClient.forecastURL(latitude: 55.6761, longitude: 12.5683, fahrenheit: true).absoluteString
        #expect(url.contains("temperature_unit=fahrenheit"))
        #expect(url.contains("latitude=55.6761"))
        #expect(url.contains("timeformat=unixtime"))
    }

    @Test func searchResultsAreToldApartAndRepeatsDropped() throws {
        let json = """
        {"results": [
          {"name": "Springfield", "latitude": 39.8, "longitude": -89.6, "country": "United States", "country_code": "US", "admin1": "Illinois", "admin2": "Sangamon"},
          {"name": "Springfield", "latitude": 37.2, "longitude": -93.3, "country": "United States", "country_code": "US", "admin1": "Missouri", "admin2": "Greene"},
          {"name": "Springfield", "latitude": 40.0, "longitude": -89.0, "country": "United States", "country_code": "US", "admin1": "Illinois", "admin2": "Logan"},
          {"name": "Mallorca", "latitude": 9.9, "longitude": -84.1, "country": "Costa Rica", "country_code": "CR", "admin1": "San José"},
          {"name": "Mallorca", "latitude": 9.9, "longitude": -84.2, "country": "Costa Rica", "country_code": "CR", "admin1": "San José"},
          {"name": "Singapore", "latitude": 1.3, "longitude": 103.8, "country": "Singapore", "country_code": "SG", "admin1": "Singapore"}
        ]}
        """
        let cities = try OpenMeteoClient.cities(from: Data(json.utf8))
        #expect(cities.map(\.detail) == [
            "Sangamon, Illinois, United States",
            "Missouri, United States",
            "Logan, Illinois, United States",
            "San José, Costa Rica",
            "Singapore",
        ])
        #expect(cities.first?.countryCode == "US")
        #expect(try OpenMeteoClient.cities(from: Data(#"{"generationtime_ms": 0.6}"#.utf8)).isEmpty)
    }

    @Test func savedCitiesShowTheirFlag() throws {
        let city = SavedCity(name: "Copenhagen", detail: "Denmark", latitude: 55.7, longitude: 12.6, countryCode: "dk")
        #expect(city.flag == "🇩🇰")
        // Saved before the country code was kept.
        let old = try JSONDecoder().decode(
            SavedCity.self, from: Data(#"{"name": "Oslo", "detail": "Norway", "latitude": 59.9, "longitude": 10.7}"#.utf8)
        )
        #expect(old.countryCode == nil)
        #expect(old.flag == nil)
    }
}
