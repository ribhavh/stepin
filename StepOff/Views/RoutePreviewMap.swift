import SwiftUI
import MapKit

/// Shows the subway ride (solid, line-colored) and the final walk (dashed) with
/// markers for board, alight, and destination.
struct RoutePreviewMap: View {
    let trip: PlannedTrip

    var body: some View {
        let rec = trip.recommendation
        Map(initialPosition: .region(region)) {
            if rec.rideStationCoords.count >= 2 {
                MapPolyline(coordinates: rec.rideStationCoords)
                    .stroke(Color(hex: rec.routeColorHex), lineWidth: 5)
            }
            MapPolyline(trip.walkPolyline)
                .stroke(.blue, style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [2, 8]))

            if let board = rec.rideStationCoords.first {
                Marker("Board", systemImage: "tram.fill", coordinate: board)
                    .tint(.green)
            }
            Marker(rec.alightStationName, systemImage: "figure.walk", coordinate: rec.alightCoord)
                .tint(.orange)
            Marker(rec.destinationName, systemImage: "mappin", coordinate: rec.destinationCoord)
                .tint(.red)
        }
        .mapControlVisibility(.hidden)
    }

    /// A region that comfortably frames every point in the trip.
    private var region: MKCoordinateRegion {
        var coords = trip.recommendation.rideStationCoords
        coords.append(trip.recommendation.alightCoord)
        coords.append(trip.recommendation.destinationCoord)

        let lats = coords.map(\.latitude)
        let lons = coords.map(\.longitude)
        let minLat = lats.min() ?? 40.75, maxLat = lats.max() ?? 40.75
        let minLon = lons.min() ?? -73.99, maxLon = lons.max() ?? -73.99

        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2,
                                            longitude: (minLon + maxLon) / 2)
        let span = MKCoordinateSpan(latitudeDelta: max((maxLat - minLat) * 1.4, 0.01),
                                    longitudeDelta: max((maxLon - minLon) * 1.4, 0.01))
        return MKCoordinateRegion(center: center, span: span)
    }
}
