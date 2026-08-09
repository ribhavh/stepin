import SwiftUI

@main
struct StepOffApp: App {
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
