import CoreLocation
import Observation

/// Keeps the current weather fresh (every 20 minutes) for the location or chosen city.
@Observable
final class WeatherService {
    enum Status: Equatable {
        case idle, loading, needsLocation, failed
    }

    private(set) var snapshot: WeatherSnapshot?
    private(set) var status = Status.idle

    @ObservationIgnored let location = LocationProvider()
    @ObservationIgnored private weak var services: AppServices?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var cachedPlaceName: (CLLocation, String)?

    static let refreshInterval: Duration = .seconds(20 * 60)

    func start(services: AppServices) {
        self.services = services
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: Self.refreshInterval)
            }
        }
    }

    var usesFahrenheit: Bool {
        switch services?.settings.temperatureUnit ?? .automatic {
        case .celsius: false
        case .fahrenheit: true
        case .automatic: Locale.current.measurementSystem == .us
        }
    }

    /// Asks for location access (from a button, never on launch) and refreshes. Turned down, the
    /// weather stops using the location, for a city instead.
    func requestLocationAccess() async {
        await location.requestAccess()
        services?.settings.weatherUseLocation = ![.denied, .restricted].contains(location.authorizationStatus)
        await refresh()
    }

    func refresh() async {
        guard let settings = services?.settings, settings.homeLayout.contains(.weather) else { return }
        if settings.weatherUseLocation, location.authorizationStatus == .notDetermined {
            status = .needsLocation
            return
        }
        status = .loading
        do {
            let latitude: Double, longitude: Double, name: String
            if !settings.weatherUseLocation, let city = settings.weatherCity {
                (latitude, longitude, name) = (city.latitude, city.longitude, city.name)
            } else if settings.weatherUseLocation {
                let current = try await location.currentLocation()
                latitude = current.coordinate.latitude
                longitude = current.coordinate.longitude
                name = await placeName(for: current)
            } else {
                status = .needsLocation
                return
            }
            snapshot = try await OpenMeteoClient.fetch(
                latitude: latitude, longitude: longitude, locationName: name, fahrenheit: usesFahrenheit
            )
            status = .idle
        } catch let error as CLError where error.code == .denied {
            status = .needsLocation
        } catch {
            status = .failed
        }
    }

    private func placeName(for location: CLLocation) async -> String {
        if let (cached, name) = cachedPlaceName, cached.distance(from: location) < 5_000 {
            return name
        }
        let name = await LocationProvider.placeName(for: location) ?? String(localized: "Current Location")
        cachedPlaceName = (location, name)
        return name
    }
}
