import SwiftUI
import MapKit
import UIKit

struct PlanView: View {
    @Bindable var model: PlannerModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    inputCard
                    resultSection
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("StepOff")
            .background(Color(.systemGroupedBackground))
        }
    }

    // MARK: Inputs

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            AddressField(label: "FROM", icon: "location.circle.fill",
                         text: $model.originText,
                         onSelect: { completion, display in
                             Task { await model.pickOrigin(completion, display: display) }
                         },
                         onEdit: { model.editedOrigin() })
            Divider()
            AddressField(label: "TO", icon: "mappin.circle.fill",
                         text: $model.destinationText,
                         onSelect: { completion, display in
                             Task { await model.pickDestination(completion, display: display) }
                         },
                         onEdit: { model.editedDestination() })
            Divider()
            targetControls
            planButton
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemGroupedBackground)))
    }

    private var targetControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("I WANT TO WALK").font(.caption2).foregroundStyle(.secondary)
            Picker("Target", selection: $model.targetMode) {
                ForEach(PlannerModel.TargetMode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            if model.targetMode == .minutes {
                Stepper(value: $model.minutes, in: 5...60, step: 5) {
                    Text("\(model.minutes) min").font(.headline)
                }
            } else {
                Stepper(value: $model.steps, in: 1000...15000, step: 500) {
                    Text("\(model.steps.formatted()) steps").font(.headline)
                }
            }
        }
    }

    private var planButton: some View {
        Button {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                            to: nil, from: nil, for: nil)
            Task { await model.plan() }
        } label: {
            HStack {
                if case .planning = model.state { ProgressView().tint(.white) }
                Text(isPlanning ? "Planning…" : "Plan my walk")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(isPlanning)
    }

    private var isPlanning: Bool {
        if case .planning = model.state { return true }
        return false
    }

    // MARK: Result

    @ViewBuilder
    private var resultSection: some View {
        switch model.state {
        case .idle:
            hint
        case .planning:
            EmptyView()
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemGroupedBackground)))
        case .result(let trip):
            RecommendationCard(trip: trip)
        }
    }

    private var hint: some View {
        VStack(spacing: 8) {
            Image(systemName: "figure.walk.motion").font(.largeTitle).foregroundStyle(.tint)
            Text("Ride most of the way, walk the rest.")
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

// MARK: - Recommendation card

struct RecommendationCard: View {
    let trip: PlannedTrip

    private var rec: Recommendation { trip.recommendation }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                SubwayLineBadge(name: rec.routeShortName, colorHex: rec.routeColorHex)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Get off at \(rec.alightStationName)")
                        .font(.title3.weight(.bold))
                    if rec.gotOffEarly {
                        Text("instead of \(rec.naturalAlightStationName)")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }

            HStack(spacing: 24) {
                stat(value: "\(Int(rec.finalWalk.minutes.rounded()))", unit: "min walk")
                stat(value: rec.finalWalk.steps(stride: WalkTarget.defaultStride).formatted(),
                     unit: "steps")
            }

            Label("Board at \(rec.boardStationName)", systemImage: "tram.fill")
                .font(.subheadline).foregroundStyle(.secondary)

            RoutePreviewMap(trip: trip)
                .frame(height: 260)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            Button(action: openInMaps) {
                Label("Open walk in Maps", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemGroupedBackground)))
    }

    private func stat(value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(.system(.title, design: .rounded).weight(.bold))
            Text(unit).font(.caption).foregroundStyle(.secondary)
        }
    }

    /// Hand the final walking leg to Apple Maps for turn-by-turn.
    private func openInMaps() {
        let alight = MKMapItem(placemark: MKPlacemark(coordinate: rec.alightCoord))
        alight.name = rec.alightStationName
        let dest = MKMapItem(placemark: MKPlacemark(coordinate: rec.destinationCoord))
        dest.name = rec.destinationName
        MKMapItem.openMaps(
            with: [alight, dest],
            launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking]
        )
    }
}
