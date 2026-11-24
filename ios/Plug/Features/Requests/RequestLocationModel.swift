import CoreLocation
import Foundation

@MainActor
final class RequestLocationModel: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    @Published var address = "" {
        didSet {
            if address != oldValue { generation = UUID(); location = nil; fixedAt = nil; label = nil; isWorking = false; geocoder.cancelGeocode() }
        }
    }
    @Published private(set) var location: RequestLocation?
    @Published private(set) var label: String?
    @Published private(set) var errorMessage: String?
    /// True when the error is that location access is off, so screens pick their copy by case.
    @Published private(set) var accessOff = false
    @Published private(set) var isWorking = false
    /// When the current device fix was taken; nil for a typed address, which does not go stale.
    private(set) var fixedAt: Date?
    static let maxFixAge: TimeInterval = 10 * 60
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
            fixedAt = nil
            label = [match.name, match.locality, match.administrativeArea].compactMap { $0 }.joined(separator: ", ")
        } catch {
            guard generation == current else { return }
            errorMessage = "The address could not be checked. Your address is kept; reconnect and try again."
        }
        if generation == current { isWorking = false }
    }

    /// A device fix older than ten minutes is asked for again before it is sent with an ask.
    func isStale(now: Date = Date()) -> Bool { Self.isStale(fixedAt: fixedAt, now: now) }
    static func isStale(fixedAt: Date?, now: Date) -> Bool {
        guard let fixedAt else { return false }
        return now.timeIntervalSince(fixedAt) > maxFixAge
    }

    func useDeviceLocation() {
        generation = UUID()
        deviceGeneration = generation
        geocoder.cancelGeocode()
        location = nil
        errorMessage = nil
        accessOff = false
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
        fixedAt = fix.timestamp
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
        accessOff = true
        errorMessage = "Location access is off. You can still search by entering an address below."
    }
}
