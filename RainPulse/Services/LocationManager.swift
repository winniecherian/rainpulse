import Foundation
import CoreLocation
import WidgetKit

/// "When In Use" location only. The last fix is saved to the App Group so the
/// widget and background rain checks can use it.
@MainActor
final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var location: CLLocation?
    @Published private(set) var status: CLAuthorizationStatus = .notDetermined
    @Published private(set) var placeName: String?

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()

    override init() {
        super.init()
        status = manager.authorizationStatus
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        if let saved = SharedStore.lastLocation {
            location = CLLocation(latitude: saved.latitude, longitude: saved.longitude)
            placeName = saved.name
        }
    }

    var isAuthorized: Bool {
        status == .authorizedWhenInUse || status == .authorizedAlways
    }

    func request() {
        switch status {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways: manager.requestLocation()
        default: break
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let newStatus = manager.authorizationStatus
        Task { @MainActor in
            self.status = newStatus
            if self.isAuthorized { self.manager.requestLocation() }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        Task { @MainActor in self.handle(latest) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}

    private func handle(_ newLocation: CLLocation) {
        location = newLocation
        geocoder.reverseGeocodeLocation(newLocation) { [weak self] marks, _ in
            let mark = marks?.first
            let name = mark?.locality ?? mark?.subAdministrativeArea ?? mark?.name
                ?? String(localized: "Current Location")
            Task { @MainActor in
                guard let self else { return }
                self.placeName = name
                SharedStore.lastLocation = Place(name: name,
                                                 latitude: newLocation.coordinate.latitude,
                                                 longitude: newLocation.coordinate.longitude,
                                                 isCurrentLocation: true)
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
    }
}
