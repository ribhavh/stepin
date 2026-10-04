import Foundation
import SwiftUI
import MapKit

/// A finished, drawable suggestion.
struct PlannedTrip {
    let recommendation: Recommendation
    let walkPolyline: MKPolyline
}

/// Orchestrates the whole flow and holds UI state. `@Observable` + `@MainActor`
/// to match the app's iOS 17 Observation style.
@MainActor
@Observable
final class PlannerModel {
    enum TargetMode: String, CaseIterable, Identifiable {
        case minutes = "Minutes"
        case steps = "Steps"
        var id: String { rawValue }
    }

    enum State {
        case idle
        case planning
        case result(PlannedTrip)
        case failed(String)
    }

    // Inputs (pre-filled with the motivating example).
    var originText = "315 W 33rd St, New York"
    var destinationText = "100 5th Ave, New York"
    var targetMode: TargetMode = .minutes
    var minutes = 20
    var steps = 4000

    private(set) var state: State = .idle

    /// Bumped each time a fresh result lands, so the view can scroll to it.
    private(set) var resultCount = 0

    // Coordinates resolved from a picked autocomplete suggestion. Used only
    // while the field text still matches what was picked; a manual edit clears
    // them and we fall back to geocoding the text.
    private var originCoord: CLLocationCoordinate2D?
    private var destinationCoord: CLLocationCoordinate2D?
    private var originResolvedText: String?
    private var destinationResolvedText: String?

    var target: WalkTarget {
        targetMode == .minutes ? .minutes(minutes) : .steps(steps)
    }

    let graph: SubwayGraph
    private let geocoder = GeocodeService()
    private let walk = WalkService()

    /// Distinct lines to evaluate. With up to `maxMeasurements` walking
    /// measurements per line, this bounds the number of (rate-limited) MapKit
    /// calls per plan (here ≤ 3×4 + 1).
    private let maxLines = 3

    init(graph: SubwayGraph) {
        self.graph = graph
    }

    /// Record a picked suggestion for the origin and resolve it to a coordinate.
    func pickOrigin(_ completion: MKLocalSearchCompletion, display: String) async {
        originText = display
        originResolvedText = display
        originCoord = await coordinate(for: completion)
    }

    /// Record a picked suggestion for the destination.
    func pickDestination(_ completion: MKLocalSearchCompletion, display: String) async {
        destinationText = display
        destinationResolvedText = display
        destinationCoord = await coordinate(for: completion)
    }

    func editedOrigin() { originCoord = nil; originResolvedText = nil }
    func editedDestination() { destinationCoord = nil; destinationResolvedText = nil }

    func plan() async {
        state = .planning
        do {
            let origin = try await resolvedPlace(text: originText,
                                                 coord: originCoord,
                                                 resolvedText: originResolvedText)
            let dest = try await resolvedPlace(text: destinationText,
                                               coord: destinationCoord,
                                               resolvedText: destinationResolvedText)

            let planner = TransitPlanner(graph: graph)
            let candidates = planner.plan(origin: origin.coordinate,
                                          destination: dest.coordinate)
            guard !candidates.isEmpty else {
                state = .failed("Couldn't find a subway trip between those places. This works for NYC subway trips.")
                return
            }

            // Nearest boarding per line, then evaluate a few of the closest.
            let distinct = bestPerLine(candidates).prefix(maxLines)

            let early = GetOffEarlyPlanner(graph: graph)
            var best: (journey: JourneyCandidate, choice: GetOffEarlyPlanner.AlightChoice)?
            for candidate in distinct {
                guard let choice = await early.bestAlight(for: candidate,
                                                          destination: dest.coordinate,
                                                          target: target,
                                                          estimator: walk) else { continue }
                // Prefer the best walk-target match; break ties by nearest boarding.
                if best == nil
                    || choice.mismatch < best!.choice.mismatch
                    || (choice.mismatch == best!.choice.mismatch
                        && candidate.boardWalkMeters < best!.journey.boardWalkMeters) {
                    best = (candidate, choice)
                }
            }

            guard let best else {
                state = .failed("Couldn't work out a walk to your destination from a nearby stop.")
                return
            }

            let trip = try await buildTrip(journey: best.journey,
                                           choice: best.choice,
                                           destination: dest)
            resultCount += 1
            state = .result(trip)
        } catch is CancellationError {
            // superseded by a newer plan; leave state alone
        } catch let error as MKError where error.code == .loadingThrottled {
            state = .failed("Maps is rate-limiting directions after several quick tries. Wait a few seconds and tap Plan again.")
        } catch is WalkError {
            state = .failed("Found a subway route, but couldn't map the walk to your destination.")
        } catch {
            state = .failed("Couldn't look up one of those addresses. Try a more specific NYC address.")
        }
    }

    // MARK: - Helpers

    /// Prefer the coordinate from a picked suggestion (when the text still
    /// matches it); otherwise geocode whatever the user typed.
    private func resolvedPlace(text: String,
                              coord: CLLocationCoordinate2D?,
                              resolvedText: String?) async throws -> GeocodeService.Place {
        if let coord, resolvedText == text {
            return GeocodeService.Place(name: text, coordinate: coord)
        }
        return try await geocoder.resolve(text)
    }

    private func coordinate(for completion: MKLocalSearchCompletion) async -> CLLocationCoordinate2D? {
        let request = MKLocalSearch.Request(completion: completion)
        guard let response = try? await MKLocalSearch(request: request).start(),
              let item = response.mapItems.first else { return nil }
        return item.placemark.coordinate
    }

    /// Keep the nearest boarding per (route, direction), ordered by how close
    /// that boarding is to the origin — i.e. the lines you'd actually take.
    private func bestPerLine(_ candidates: [JourneyCandidate]) -> [JourneyCandidate] {
        var seen: [String: JourneyCandidate] = [:]   // "route|dir" -> nearest boarding
        for c in candidates {
            let key = "\(c.pattern.route)|\(c.pattern.direction)"
            if let existing = seen[key], existing.boardWalkMeters <= c.boardWalkMeters { continue }
            seen[key] = c
        }
        return seen.values.sorted { $0.boardWalkMeters < $1.boardWalkMeters }
    }

    private func buildTrip(journey: JourneyCandidate,
                           choice: GetOffEarlyPlanner.AlightChoice,
                           destination: GeocodeService.Place) async throws -> PlannedTrip {
        let pattern = journey.pattern
        let alightIndex = choice.alightIndex
        let stationIds = Array(pattern.stations[journey.boardIndex...alightIndex])
        let names = stationIds.map { graph.name(of: $0) }
        let coords = stationIds.compactMap { graph.coordinate(of: $0) }

        guard let alightCoord = graph.coordinate(of: pattern.stations[alightIndex]) else {
            throw WalkError.noRoute
        }

        // One precise route for the chosen alight → destination, for the map and
        // the displayed numbers.
        let routeResult = try await walk.route(from: alightCoord,
                                               to: destination.coordinate)

        let info = graph.routes[journey.routeId]
        let recommendation = Recommendation(
            routeId: journey.routeId,
            routeShortName: info?.short_name ?? journey.routeId,
            routeColorHex: info?.color ?? "",
            boardStationName: graph.name(of: journey.boardStationId),
            alightStationName: graph.name(of: pattern.stations[alightIndex]),
            naturalAlightStationName: graph.name(of: journey.naturalAlightStationId),
            gotOffEarly: alightIndex < journey.naturalAlightIndex,
            rideStationNames: names,
            rideStationCoords: coords,
            stops: alightIndex - journey.boardIndex,
            finalWalk: routeResult.measure,
            alightCoord: alightCoord,
            destinationCoord: destination.coordinate,
            destinationName: destination.name
        )
        return PlannedTrip(recommendation: recommendation, walkPolyline: routeResult.polyline)
    }
}
