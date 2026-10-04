import SwiftUI

@main
struct StepsInApp: App {
    private let graph: SubwayGraph

    init() {
        graph = SubwayGraph.loadBundled()
    }

    var body: some Scene {
        WindowGroup {
            PlanView(model: PlannerModel(graph: graph))
        }
    }
}
