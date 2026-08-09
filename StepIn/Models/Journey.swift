import Foundation
import CoreLocation

/// A natural single-line subway trip (before any "get off early" adjustment),
/// produced by `TransitPlanner`. Board and alight are indices into the
/// pattern's ordered station list, so the ride always goes forward.
struct JourneyCandidate {
    let pattern: StopPattern
    let boardIndex: Int
    let naturalAlightIndex: Int
    let boardWalkMeters: Double          // straight-line origin -> board station
    let naturalAlightWalkMeters: Double  // straight-line natural alight -> destination

    var routeId: String { pattern.route }
    var numStops: Int { naturalAlightIndex - boardIndex }
    var boardStationId: String { pattern.stations[boardIndex] }
    var naturalAlightStationId: String { pattern.stations[naturalAlightIndex] }

    /// Straight-line planning cost used to pick the natural best line: minimize
    /// walking, with a small per-stop nudge so we don't ride needlessly far.
    var planningCost: Double {
        boardWalkMeters + naturalAlightWalkMeters
            + Double(numStops) * TransitPlanner.ridePerStopMeters
    }
}

/// The finished suggestion shown to the user: which line to take, where to get
/// off (possibly earlier than natural), and the resulting walk.
struct Recommendation {
    let routeId: String
    let routeShortName: String
    let routeColorHex: String

    let boardStationName: String
    let alightStationName: String        // where to actually get off
    let naturalAlightStationName: String // the "instead of…" stop
    let gotOffEarly: Bool                // alight is earlier than natural

    let rideStationNames: [String]              // board … alight, inclusive
    let rideStationCoords: [CLLocationCoordinate2D]

    let finalWalk: WalkMeasure
    let alightCoord: CLLocationCoordinate2D
    let destinationCoord: CLLocationCoordinate2D
    let destinationName: String
}
