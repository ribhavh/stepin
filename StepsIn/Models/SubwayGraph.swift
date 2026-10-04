import Foundation
import CoreLocation

// MARK: - Decoded GTFS bundle (produced by Scripts/build_mta_data.py)

struct StationInfo: Decodable {
    let name: String
    let lat: Double
    let lon: Double
}

struct RouteInfo: Decodable {
    let short_name: String
    let long_name: String
    let color: String   // 6-hex, may be empty
}

/// One distinct ordered station sequence for a route in a single travel
/// direction. Express and local services produce different patterns for the
/// same route (the A skips stops the C makes), so each is kept separately.
struct StopPattern: Decodable {
    let route: String
    let direction: Int
    let stations: [String]   // parent-station ids, in travel order
    let count: Int           // number of trips using this exact sequence
}

struct Transfer: Decodable {
    let from: String
    let to: String
    let min_time: Int
}

private struct SubwayData: Decodable {
    let stations: [String: StationInfo]
    let routes: [String: RouteInfo]
    let patterns: [StopPattern]
    let transfers: [Transfer]
}

// MARK: - SubwayGraph

/// In-memory view of the distilled subway network. Pure and value-like: all
/// lookups are synchronous and network-free, which keeps the planners testable.
struct SubwayGraph {
    let stations: [String: StationInfo]
    let routes: [String: RouteInfo]
    let patterns: [StopPattern]
    let transfers: [Transfer]

    init(stations: [String: StationInfo],
         routes: [String: RouteInfo],
         patterns: [StopPattern],
         transfers: [Transfer]) {
        self.stations = stations
        self.routes = routes
        self.patterns = patterns
        self.transfers = transfers
    }

    // MARK: Loading

    static func loadBundled(filename: String = "mta_subway") -> SubwayGraph {
        guard let url = Bundle.main.url(forResource: filename, withExtension: "json") else {
            fatalError("Missing \(filename).json in app bundle. Run Scripts/build_mta_data.py.")
        }
        return load(contentsOf: url)
    }

    static func load(contentsOf url: URL) -> SubwayGraph {
        do {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode(SubwayData.self, from: data)
            return SubwayGraph(stations: decoded.stations,
                               routes: decoded.routes,
                               patterns: decoded.patterns,
                               transfers: decoded.transfers)
        } catch {
            fatalError("Could not load subway data at \(url): \(error)")
        }
    }

    // MARK: Lookups

    func station(_ id: String) -> StationInfo? { stations[id] }

    func name(of id: String) -> String { stations[id]?.name ?? id }

    func coordinate(of id: String) -> CLLocationCoordinate2D? {
        guard let s = stations[id] else { return nil }
        return CLLocationCoordinate2D(latitude: s.lat, longitude: s.lon)
    }

    /// Stations nearest a coordinate by straight-line distance, closest first.
    /// Used to seed board/alight candidates before precise walking routing.
    func nearestStations(to coord: CLLocationCoordinate2D,
                         limit: Int = 6,
                         maxMeters: Double = 1500) -> [(id: String, meters: Double)] {
        let origin = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        var scored: [(String, Double)] = []
        scored.reserveCapacity(stations.count)
        for (id, s) in stations {
            let d = origin.distance(from: CLLocation(latitude: s.lat, longitude: s.lon))
            if d <= maxMeters { scored.append((id, d)) }
        }
        scored.sort { $0.1 < $1.1 }
        return scored.prefix(limit).map { (id: $0.0, meters: $0.1) }
    }
}
