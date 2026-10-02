import CoreLocation
import MapKit
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

/// A real business found by Apple Maps near the request (ADR-009). It is a listing, not an
/// offer: PLUG has not contacted it, so price and availability are always shown as Unknown.
struct NearbyBusiness: Identifiable, Equatable {
    let id: String
    let name: String
    let address: String?
    let distanceM: Int
    let phone: String?
    let mapItem: MKMapItem
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
}

/// Searches Apple Maps on the device with the server's validated search terms. Nothing is
/// sent to PLUG and nothing is stored; the search is repeated only when the request changes.
@MainActor
final class NearbyBusinessesModel: ObservableObject {
    enum Phase: Equatable { case idle, searching, loaded, empty, failed }
    @Published private(set) var businesses: [NearbyBusiness] = []
    @Published private(set) var phase: Phase = .idle
    private var searchedKey: String?

    func search(terms: [String], around location: RequestLocation, radiusM: Int, force: Bool = false) async {
        let key = "\(terms.joined(separator: "|"))@\(location.latitude),\(location.longitude)/\(radiusM)"
        guard !terms.isEmpty, force || key != searchedKey else { return }
        searchedKey = key
        phase = .searching
        let origin = CLLocation(latitude: location.latitude, longitude: location.longitude)
        let region = MKCoordinateRegion(center: origin.coordinate,
                                        latitudinalMeters: Double(radiusM) * 2, longitudinalMeters: Double(radiusM) * 2)
        var found: [String: NearbyBusiness] = [:]
        var failures = 0
        for term in terms.prefix(3) {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = term
            request.resultTypes = .pointOfInterest
            request.region = region
            do {
                let response = try await MKLocalSearch(request: request).start()
                for item in response.mapItems {
                    guard let name = item.name, let place = item.placemark.location else { continue }
                    let distance = Int(place.distance(from: origin).rounded())
                    guard distance <= radiusM else { continue }
                    let id = "\(name)|\(Int(place.coordinate.latitude * 10_000))|\(Int(place.coordinate.longitude * 10_000))"
                    found[id] = NearbyBusiness(id: id, name: name, address: item.placemark.title,
                                               distanceM: distance, phone: item.phoneNumber, mapItem: item)
                }
            } catch { failures += 1 }
            guard searchedKey == key else { return }
        }
        businesses = found.values.sorted { ($0.distanceM, $0.name) < ($1.distanceM, $1.name) }.prefix(12).map { $0 }
        phase = !businesses.isEmpty ? .loaded : failures == min(terms.count, 3) ? .failed : .empty
    }

    func reset() { businesses = []; phase = .idle; searchedKey = nil }
}
