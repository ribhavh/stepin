import Foundation
import MapKit

enum GeocodeError: Error { case notFound }

/// Resolves an address or place name to a coordinate via MapKit local search,
/// biased to NYC so "100 5th Ave" lands in Manhattan.
final class GeocodeService {
    struct Place {
        let name: String
        let coordinate: CLLocationCoordinate2D
    }

    /// Rough bounding region for NYC, used to bias search results.
    static let nycRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 40.7128, longitude: -73.9860),
        span: MKCoordinateSpan(latitudeDelta: 0.6, longitudeDelta: 0.6)
    )

    func resolve(_ query: String) async throws -> Place {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = Self.nycRegion

        let response = try await MKLocalSearch(request: request).start()
        guard let item = response.mapItems.first else { throw GeocodeError.notFound }
        return Place(name: item.name ?? query,
                     coordinate: item.placemark.coordinate)
    }
}
