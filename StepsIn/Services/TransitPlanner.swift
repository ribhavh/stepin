import Foundation
import CoreLocation

/// Finds natural single-line subway trips between two coordinates. Pure and
/// synchronous over `SubwayGraph` (no network, no MapKit), so it is fully
/// unit-testable. The "get off early" adjustment happens afterward in
/// `GetOffEarlyPlanner`.
///
/// Line choice is anchored on the *origin* — the line you'd actually board —
/// not on minimizing the destination walk. That matters because the whole point
/// of "walk 20 minutes" is to *want* a long final walk, so a line that lands
/// closest to the destination is exactly the wrong thing to prefer.
struct TransitPlanner {
    /// Straight-line meters "charged" per stop ridden — small, so the planner
    /// prefers shorter walks but won't ride many extra stops to shave a block.
    static let ridePerStopMeters = 120.0

    let graph: SubwayGraph

    var boardSearchRadius = 1300.0
    var boardCandidateLimit = 8
    var alightSearchRadius = 2500.0
    var alightCandidateLimit = 25

    /// The line must actually serve the destination's neighborhood: its closest
    /// stop to the destination has to be within this straight-line distance.
    /// Otherwise get-off-early could match the target walk at some stop that
    /// happens to be ~20 min away but nowhere near where you're going.
    var nearDestinationCap = 2000.0

    /// Candidate journeys, closest boarding first. One per (board, line); the
    /// caller narrows to a few lines and runs get-off-early on each.
    func plan(origin: CLLocationCoordinate2D,
              destination: CLLocationCoordinate2D) -> [JourneyCandidate] {
        let boards = graph.nearestStations(to: origin,
                                           limit: boardCandidateLimit,
                                           maxMeters: boardSearchRadius)
        let alights = graph.nearestStations(to: destination,
                                            limit: alightCandidateLimit,
                                            maxMeters: alightSearchRadius)
        guard !boards.isEmpty, !alights.isEmpty else { return [] }

        let boardMeters = Dictionary(boards.map { ($0.id, $0.meters) },
                                     uniquingKeysWith: min)
        let alightMeters = Dictionary(alights.map { ($0.id, $0.meters) },
                                      uniquingKeysWith: min)
        let dest = CLLocation(latitude: destination.latitude, longitude: destination.longitude)

        var candidates: [JourneyCandidate] = []
        for pattern in graph.patterns {
            // Where do our board/alight candidates sit within this pattern?
            var boardHits: [(idx: Int, meters: Double)] = []
            var alightHits: [(idx: Int, meters: Double)] = []
            for (i, sid) in pattern.stations.enumerated() {
                if let m = boardMeters[sid] { boardHits.append((i, m)) }
                if let m = alightMeters[sid] { alightHits.append((i, m)) }
            }
            guard !boardHits.isEmpty, !alightHits.isEmpty else { continue }

            for board in boardHits {
                // Natural alight: the stop after boarding that is closest to the
                // destination (the far end of the ride).
                let forward = alightHits.filter { $0.idx > board.idx }
                guard let natural = forward.min(by: { $0.meters < $1.meters }) else { continue }
                guard natural.meters <= nearDestinationCap else { continue }

                // The ride must actually carry you toward the destination.
                guard let boardCoord = graph.coordinate(of: pattern.stations[board.idx]) else { continue }
                let boardToDest = dest.distance(from: CLLocation(latitude: boardCoord.latitude,
                                                                 longitude: boardCoord.longitude))
                guard natural.meters < boardToDest else { continue }

                candidates.append(JourneyCandidate(
                    pattern: pattern,
                    boardIndex: board.idx,
                    naturalAlightIndex: natural.idx,
                    boardWalkMeters: board.meters,
                    naturalAlightWalkMeters: natural.meters
                ))
            }
        }

        candidates.sort { $0.boardWalkMeters < $1.boardWalkMeters }
        return candidates
    }
}
