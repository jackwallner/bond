import CoreLocation
import Foundation

@MainActor
final class LocationService: NSObject, CLLocationManagerDelegate {
    static let shared = LocationService()

    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation, Error>?

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    /// Geofence reminders fire through `UNLocationNotificationTrigger`, which
    /// only needs When-In-Use authorization — Bond never does continuous
    /// background location, so we never request "Always" (declaring it without
    /// using it is an App Review rejection vector).
    func requestAuthorizationIfNeeded() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }

    struct LocationDeniedError: LocalizedError {
        var errorDescription: String? {
            "Location access is off for Bond. Enable it in Settings → Privacy & Security → Location Services."
        }
    }

    /// One-shot current location — used as the default geofence anchor.
    func currentLocation() async throws -> CLLocation {
        manager.requestWhenInUseAuthorization()
        if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted {
            throw LocationDeniedError()
        }
        // A second tap before the first fix lands would silently orphan the
        // first continuation (an awaiting task that never resumes) — fail it
        // fast and let the newest request own the delegate callbacks.
        if let pending = continuation {
            continuation = nil
            pending.resume(throwing: CLError(.locationUnknown))
        }
        return try await withCheckedThrowingContinuation { cont in
            self.continuation = cont
            manager.requestLocation()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            if let loc = locations.last {
                self.continuation?.resume(returning: loc)
                self.continuation = nil
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.continuation?.resume(throwing: error)
            self.continuation = nil
        }
    }
}
