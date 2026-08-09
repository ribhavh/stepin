import Foundation
import MapKit

/// Abstraction over "how long is the walk between two points," so the
/// get-off-early planner can be unit-tested with a stub instead of MapKit.
protocol WalkEstimating {
    func measure(from: CLLocationCoordinate2D,
                 to: CLLocationCoordinate2D) async throws -> WalkMeasure
}

enum WalkError: Error { case noRoute }

/// Real walking distances/times (and a drawable route) from MapKit. This is the
/// one thing MapKit does well for us — transit routing is unsupported, but
/// `.walking` directions are accurate and give a polyline for the map.
final class WalkService: WalkEstimating {
    struct RouteResult {
        let measure: WalkMeasure
        let polyline: MKPolyline
    }

    func route(from: CLLocationCoordinate2D,
               to: CLLocationCoordinate2D) async throws -> RouteResult {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: from))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: to))
        request.transportType = .walking

        let response = try await MKDirections(request: request).calculate()
        guard let route = response.routes.first else { throw WalkError.noRoute }
        return RouteResult(
            measure: WalkMeasure(distanceMeters: route.distance,
                                 timeSeconds: route.expectedTravelTime),
            polyline: route.polyline
        )
    }

    func measure(from: CLLocationCoordinate2D,
                 to: CLLocationCoordinate2D) async throws -> WalkMeasure {
        try await route(from: from, to: to).measure
    }
}
