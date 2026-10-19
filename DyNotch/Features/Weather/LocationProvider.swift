import CoreLocation
import MapKit

/// One-shot approximate location for the weather.
final class LocationProvider: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuations: [CheckedContinuation<CLLocation, Error>] = []
    private var accessContinuations: [CheckedContinuation<Void, Never>] = []

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    var authorizationStatus: CLAuthorizationStatus { manager.authorizationStatus }

    /// Shows the system's prompt unless it's been answered, and returns once it is.
    func requestAccess() async {
        guard manager.authorizationStatus == .notDetermined else { return }
        await withCheckedContinuation { continuation in
            accessContinuations.append(continuation)
            manager.requestWhenInUseAuthorization()
        }
    }

    func currentLocation() async throws -> CLLocation {
        if let location = manager.location, location.timestamp.timeIntervalSinceNow > -15 * 60 {
            return location
        }
        return try await withCheckedThrowingContinuation { continuation in
            continuations.append(continuation)
            if manager.authorizationStatus == .notDetermined {
                manager.requestWhenInUseAuthorization()
            } else {
                manager.requestLocation()
            }
        }
    }

    /// City name for a location (e.g. "Copenhagen").
    static func placeName(for location: CLLocation) async -> String? {
        guard let request = MKReverseGeocodingRequest(location: location),
              let item = try? await request.mapItems.first
        else { return nil }
        return item.addressRepresentations?.cityName ?? item.name
    }

    private func finish(_ result: Result<CLLocation, Error>) {
        let pending = continuations
        continuations = []
        pending.forEach { $0.resume(with: result) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_: CLLocationManager) {
        MainActor.assumeIsolated {
            if manager.authorizationStatus != .notDetermined {
                let answered = accessContinuations
                accessContinuations = []
                answered.forEach { $0.resume() }
            }
            guard !continuations.isEmpty else { return }
            switch manager.authorizationStatus {
            case .notDetermined: break
            case .denied, .restricted: finish(.failure(CLError(.denied)))
            default: manager.requestLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        MainActor.assumeIsolated { finish(.success(location)) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        MainActor.assumeIsolated { finish(.failure(error)) }
    }
}
