import CoreLocation
import Foundation

@MainActor
final class LocationProvider: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<String, Error>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func currentLocationName() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation

            switch manager.authorizationStatus {
            case .notDetermined:
                manager.requestWhenInUseAuthorization()
            case .authorizedWhenInUse, .authorizedAlways:
                manager.requestLocation()
            case .denied, .restricted:
                continuation.resume(throwing: LocationError.permissionDenied)
                self.continuation = nil
            @unknown default:
                continuation.resume(throwing: LocationError.permissionDenied)
                self.continuation = nil
            }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
                manager.requestLocation()
            } else if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted {
                continuation?.resume(throwing: LocationError.permissionDenied)
                continuation = nil
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.first else {
            Task { @MainActor in
                continuation?.resume(throwing: LocationError.noLocation)
                continuation = nil
            }
            return
        }

        Task { @MainActor in
            do {
                let name = try await reverseGeocode(location)
                continuation?.resume(returning: name)
            } catch {
                continuation?.resume(throwing: error)
            }
            continuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }

    private func reverseGeocode(_ location: CLLocation) async throws -> String {
        let placemarks = try await CLGeocoder().reverseGeocodeLocation(location)
        guard let placemark = placemarks.first else {
            throw LocationError.noLocation
        }

        return [
            placemark.name,
            placemark.locality,
            placemark.administrativeArea
        ]
        .compactMap { $0 }
        .removingDuplicates()
        .joined(separator: ", ")
    }
}

enum LocationError: LocalizedError {
    case permissionDenied
    case noLocation

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Location access is not enabled for Trip Ledger."
        case .noLocation:
            return "Trip Ledger could not determine your current location."
        }
    }
}

private extension Array where Element: Hashable {
    func removingDuplicates() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
