import Foundation
import CoreLocation

/// Given a natural journey, decides which stop to actually get off at so the
/// remaining walk best matches the user's target. Walks *backward* from the
/// natural alight toward the boarding stop — earlier stops are further from the
/// destination, so they add walking.
///
/// The routing/ranking is pure; precise walking measurements are supplied via an
/// injected `WalkEstimating`, so tests can drive it with a deterministic stub.
struct GetOffEarlyPlanner {
    let graph: SubwayGraph
    var stride = WalkTarget.defaultStride

    /// Cap on precise (rate-limited) walking measurements per journey. We
    /// pre-rank stops by straight-line distance and only measure the most
    /// promising few.
    var maxMeasurements = 3

    /// Manhattan street walking is ~35% longer than the straight-line distance
    /// (the grid forces detours). We pre-rank stops by straight-line distance,
    /// so the target (a *walked* distance) is scaled down by this factor to
    /// compare like with like. Without it the pre-rank is biased toward stops
    /// that are too far and the real best stop can fall outside the measured set.
    var manhattanDetourFactor = 1.35

    struct AlightChoice {
        let alightIndex: Int
        let walk: WalkMeasure
        let mismatch: Double   // in the target's unit; lower is better
    }

    func bestAlight(for journey: JourneyCandidate,
                    destination: CLLocationCoordinate2D,
                    target: WalkTarget,
                    estimator: WalkEstimating) async -> AlightChoice? {
        let pattern = journey.pattern
        let earliest = journey.boardIndex + 1          // must ride ≥ 1 stop
        let natural = journey.naturalAlightIndex
        guard natural >= earliest else { return nil }

        // Pre-rank candidate alight stops by how close their straight-line
        // distance to the destination is to the (straight-line-scaled) target,
        // then spend precise measurements only on the top few.
        let straightTarget = target.approximateMeters(stride: stride) / manhattanDetourFactor
        let dest = CLLocation(latitude: destination.latitude, longitude: destination.longitude)

        let ranked = (earliest...natural).compactMap { idx -> (idx: Int, straight: Double)? in
            guard let c = graph.coordinate(of: pattern.stations[idx]) else { return nil }
            let d = dest.distance(from: CLLocation(latitude: c.latitude, longitude: c.longitude))
            return (idx, d)
        }
        .sorted { abs($0.straight - straightTarget) < abs($1.straight - straightTarget) }
        .prefix(maxMeasurements)

        var best: AlightChoice?
        for candidate in ranked {
            guard let coord = graph.coordinate(of: pattern.stations[candidate.idx]),
                  let walk = try? await estimator.measure(from: coord, to: destination)
            else { continue }
            let mismatch = target.mismatch(for: walk, stride: stride)
            if best == nil || mismatch < best!.mismatch {
                best = AlightChoice(alightIndex: candidate.idx, walk: walk, mismatch: mismatch)
            }
        }
        return best
    }
}
