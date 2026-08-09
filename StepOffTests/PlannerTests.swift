import XCTest
import CoreLocation
@testable import StepOff

// A straight north–south synthetic line of 5 stations 400 m apart, with a
// destination 100 m north of the last stop. Earlier (southern) stops are
// progressively further from the destination.
private func makeGraph() -> SubwayGraph {
    let baseLat = 40.7000
    let lon = -73.9900
    let step = 0.0036            // ~400 m in latitude
    var stations: [String: StationInfo] = [:]
    var ids: [String] = []
    for i in 0..<5 {
        let id = "s\(i)"
        ids.append(id)
        stations[id] = StationInfo(name: "Stop \(i)", lat: baseLat + Double(i) * step, lon: lon)
    }
    let pattern = StopPattern(route: "C", direction: 0, stations: ids, count: 100)
    let routes = ["C": RouteInfo(short_name: "C", long_name: "Test Local", color: "0039A6")]
    return SubwayGraph(stations: stations, routes: routes, patterns: [pattern], transfers: [])
}

/// Deterministic stand-in for MapKit: walk = straight-line distance, ~3 mph.
private struct StraightLineEstimator: WalkEstimating {
    func measure(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) async throws -> WalkMeasure {
        let d = CLLocation(latitude: from.latitude, longitude: from.longitude)
            .distance(from: CLLocation(latitude: to.latitude, longitude: to.longitude))
        return WalkMeasure(distanceMeters: d, timeSeconds: d / WalkTarget.metersPerSecond)
    }
}

final class WalkTargetTests: XCTestCase {
    func testStepsAndMinutesFromMeasure() {
        let walk = WalkMeasure(distanceMeters: 1520, timeSeconds: 600)
        XCTAssertEqual(walk.steps(stride: 0.76), 2000)
        XCTAssertEqual(walk.minutes, 10, accuracy: 0.001)
    }

    func testMismatchIsZeroOnTarget() {
        let walk = WalkMeasure(distanceMeters: 1520, timeSeconds: 600)
        XCTAssertEqual(WalkTarget.steps(2000).mismatch(for: walk, stride: 0.76), 0, accuracy: 0.001)
        XCTAssertEqual(WalkTarget.minutes(10).mismatch(for: walk, stride: 0.76), 0, accuracy: 0.001)
    }

    func testApproximateMeters() {
        XCTAssertEqual(WalkTarget.steps(4000).approximateMeters(stride: 0.76), 3040, accuracy: 0.001)
        XCTAssertEqual(WalkTarget.minutes(20).approximateMeters(), 20 * 1.34 * 60, accuracy: 0.001)
    }
}

final class TransitPlannerTests: XCTestCase {
    func testFindsNaturalBoardAndAlight() {
        let graph = makeGraph()
        let origin = CLLocationCoordinate2D(latitude: 40.7000, longitude: -73.9900)   // at s0
        let dest = CLLocationCoordinate2D(latitude: 40.7153, longitude: -73.9900)      // 100 m past s4

        let candidates = TransitPlanner(graph: graph).plan(origin: origin, destination: dest)
        let best = try! XCTUnwrap(candidates.first)
        XCTAssertEqual(best.boardStationId, "s0")
        XCTAssertEqual(best.naturalAlightStationId, "s4")   // closest to destination
    }
}

final class GetOffEarlyPlannerTests: XCTestCase {
    func testBacksOffToStopClosestToTarget() async throws {
        let graph = makeGraph()
        let dest = CLLocationCoordinate2D(latitude: 40.7153, longitude: -73.9900)
        // s0..s4 board→alight; walking distances to dest ≈ 1300/900/500/100 m for s1..s4.
        let journey = JourneyCandidate(pattern: graph.patterns[0],
                                       boardIndex: 0,
                                       naturalAlightIndex: 4,
                                       boardWalkMeters: 0,
                                       naturalAlightWalkMeters: 100)

        // 11 min ≈ 884 m → the ~900 m stop (s2, index 2) is the best match.
        let result = await GetOffEarlyPlanner(graph: graph).bestAlight(
            for: journey,
            destination: dest,
            target: .minutes(11),
            estimator: StraightLineEstimator()
        )
        let choice = try XCTUnwrap(result)
        XCTAssertEqual(choice.alightIndex, 2)
    }

    func testShortTargetKeepsNaturalAlight() async throws {
        let graph = makeGraph()
        let dest = CLLocationCoordinate2D(latitude: 40.7153, longitude: -73.9900)
        let journey = JourneyCandidate(pattern: graph.patterns[0],
                                       boardIndex: 0,
                                       naturalAlightIndex: 4,
                                       boardWalkMeters: 0,
                                       naturalAlightWalkMeters: 100)

        // A tiny 2-min target is best served by the closest stop (s4, the natural alight).
        let result = await GetOffEarlyPlanner(graph: graph).bestAlight(
            for: journey,
            destination: dest,
            target: .minutes(2),
            estimator: StraightLineEstimator()
        )
        let choice = try XCTUnwrap(result)
        XCTAssertEqual(choice.alightIndex, 4)
    }
}
