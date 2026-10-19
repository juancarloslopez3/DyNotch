import Foundation

nonisolated struct HourlyForecast: Identifiable, Equatable, Sendable {
    var id: Date { time }
    let time: Date
    let temperature: Double
    let code: Int
    let isDay: Bool
}

nonisolated struct WeatherSnapshot: Equatable, Sendable {
    let temperature: Double
    let apparentTemperature: Double
    let code: Int
    let isDay: Bool
    let high: Double
    let low: Double
    let hourly: [HourlyForecast]
    let isFahrenheit: Bool
    var locationName: String
    let fetchedAt: Date

    var symbol: String { WeatherCodes.symbol(for: code, isDay: isDay) }
    var conditions: String { WeatherCodes.description(for: code) }
}

/// Free weather and geocoding from open-meteo.com (no API key).
nonisolated enum OpenMeteoClient {
    struct Forecast: Decodable {
        struct Current: Decodable {
            let temperature_2m: Double
            let apparent_temperature: Double
            let weather_code: Int
            let is_day: Int
        }
        struct Hourly: Decodable {
            let time: [TimeInterval]
            let temperature_2m: [Double]
            let weather_code: [Int]
            let is_day: [Int]
        }
        struct Daily: Decodable {
            let temperature_2m_max: [Double]
            let temperature_2m_min: [Double]
        }
        let current: Current
        let hourly: Hourly
        let daily: Daily
    }

    struct GeocodingResponse: Decodable {
        struct Result: Decodable {
            let name: String
            let latitude: Double
            let longitude: Double
            let country: String?
            let country_code: String?
            let admin1: String?
            let admin2: String?
        }
        let results: [Result]?
    }

    static func forecastURL(latitude: Double, longitude: Double, fahrenheit: Bool) -> URL {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.4f", latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.4f", longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,apparent_temperature,weather_code,is_day"),
            URLQueryItem(name: "hourly", value: "temperature_2m,weather_code,is_day"),
            URLQueryItem(name: "daily", value: "temperature_2m_max,temperature_2m_min"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "timeformat", value: "unixtime"),
            URLQueryItem(name: "forecast_days", value: "2"),
            URLQueryItem(name: "temperature_unit", value: fahrenheit ? "fahrenheit" : "celsius"),
        ]
        return components.url!
    }

    static func parse(_ data: Data, locationName: String, fahrenheit: Bool, now: Date = .now) throws -> WeatherSnapshot {
        let forecast = try JSONDecoder().decode(Forecast.self, from: data)
        let hourly = forecast.hourly
        let count = min(hourly.time.count, hourly.temperature_2m.count, hourly.weather_code.count, hourly.is_day.count)
        let upcoming = (0..<count)
            .map { index in
                HourlyForecast(
                    time: Date(timeIntervalSince1970: hourly.time[index]),
                    temperature: hourly.temperature_2m[index],
                    code: hourly.weather_code[index],
                    isDay: hourly.is_day[index] == 1
                )
            }
            .filter { $0.time > now }
            .prefix(5)
        return WeatherSnapshot(
            temperature: forecast.current.temperature_2m,
            apparentTemperature: forecast.current.apparent_temperature,
            code: forecast.current.weather_code,
            isDay: forecast.current.is_day == 1,
            high: forecast.daily.temperature_2m_max.first ?? forecast.current.temperature_2m,
            low: forecast.daily.temperature_2m_min.first ?? forecast.current.temperature_2m,
            hourly: Array(upcoming),
            isFahrenheit: fahrenheit,
            locationName: locationName,
            fetchedAt: now
        )
    }

    static func fetch(latitude: Double, longitude: Double, locationName: String, fahrenheit: Bool) async throws -> WeatherSnapshot {
        let (data, response) = try await URLSession.shared.data(from: forecastURL(latitude: latitude, longitude: longitude, fahrenheit: fahrenheit))
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try parse(data, locationName: locationName, fahrenheit: fahrenheit)
    }

    static func searchURL(_ query: String) -> URL {
        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        components.queryItems = [
            URLQueryItem(name: "name", value: query),
            URLQueryItem(name: "count", value: "8"),
            URLQueryItem(name: "language", value: Locale.current.language.languageCode?.identifier ?? "en"),
            URLQueryItem(name: "format", value: "json"),
        ]
        return components.url!
    }

    /// The places in a geocoding response, best match first. Places that would read the same
    /// (two Springfields in one state) gain their county, and any left alike are dropped.
    static func cities(from data: Data) throws -> [SavedCity] {
        let results = try JSONDecoder().decode(GeocodingResponse.self, from: data).results ?? []
        func detail(_ result: GeocodingResponse.Result, withCounty: Bool) -> String {
            // The region is left out when it only repeats the name ("Singapore, Singapore").
            let region = result.admin1 == result.name || result.admin1 == result.country ? nil : result.admin1
            return [withCounty ? result.admin2 : nil, region, result.country]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: ", ")
        }
        let plain = results.map { detail($0, withCounty: false) }
        var cities: [SavedCity] = []
        for (index, result) in results.enumerated() {
            let isAmbiguous = results.indices.contains { other in
                other != index && results[other].name == result.name && plain[other] == plain[index]
            }
            let city = SavedCity(
                name: result.name,
                detail: detail(result, withCounty: isAmbiguous),
                latitude: result.latitude,
                longitude: result.longitude,
                countryCode: result.country_code
            )
            if !cities.contains(where: { $0.name == city.name && $0.detail == city.detail }) {
                cities.append(city)
            }
        }
        return cities
    }

    static func searchCities(_ query: String) async throws -> [SavedCity] {
        let (data, response) = try await URLSession.shared.data(from: searchURL(query))
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try cities(from: data)
    }
}
