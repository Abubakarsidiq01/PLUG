import CoreLocation
import Foundation

@MainActor
final class RequestLocationModel: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    @Published var address = "" {
        didSet {
            if address != oldValue { generation = UUID(); location = nil; label = nil; isWorking = false; geocoder.cancelGeocode() }
        }
    }
    @Published private(set) var location: RequestLocation?
    @Published private(set) var label: String?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isWorking = false
    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var generation = UUID()
    private var deviceGeneration: UUID?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func resolveAddress() async {
        let value = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= 200 else {
            errorMessage = "Enter a street address and city, up to 200 characters."
            return
        }
        generation = UUID()
        let current = generation
        geocoder.cancelGeocode()
        deviceGeneration = nil
        location = nil
        errorMessage = nil
        isWorking = true
        do {
            let matches = try await geocoder.geocodeAddressString(value)
            guard generation == current else { return }
            guard matches.count == 1, let match = matches.first, let coordinate = match.location?.coordinate else {
                errorMessage = "We could not identify one location. Add the street, city and state, then try again."
                isWorking = false
                return
            }
            location = RequestLocation(latitude: coordinate.latitude, longitude: coordinate.longitude, precision: .coarse)
            label = [match.name, match.locality, match.administrativeArea].compactMap { $0 }.joined(separator: ", ")
        } catch {
            guard generation == current else { return }
            errorMessage = "The address could not be checked. Your address is kept; reconnect and try again."
        }
        if generation == current { isWorking = false }
    }

    func useDeviceLocation() {
        generation = UUID()
        deviceGeneration = generation
        geocoder.cancelGeocode()
        location = nil
        errorMessage = nil
        isWorking = true
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse: manager.requestLocation()
        default: denied()
        }
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard deviceGeneration == generation else { return }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: manager.requestLocation()
        case .denied, .restricted: denied()
        default: break
        }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard deviceGeneration == generation else { return }
        deviceGeneration = nil
        isWorking = false
        guard let fix = locations.last, fix.horizontalAccuracy >= 0,
              abs(fix.timestamp.timeIntervalSinceNow) < 120 else {
            errorMessage = "A current location is unavailable. Enter an address below."
            return
        }
        location = RequestLocation(latitude: fix.coordinate.latitude, longitude: fix.coordinate.longitude, precision: .coarse)
        label = "Current approximate location"
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard deviceGeneration == generation else { return }
        deviceGeneration = nil
        isWorking = false
        errorMessage = "Location is unavailable. Enter an address below to continue."
    }
    private func denied() {
        deviceGeneration = nil
        isWorking = false
        errorMessage = "Location access is off. You can still search by entering an address below."
    }
}
