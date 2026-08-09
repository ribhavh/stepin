import Foundation

/// A measured walking segment: real distance and time from MapKit (or a stub
/// estimator in tests).
struct WalkMeasure: Equatable {
    let distanceMeters: Double
    let timeSeconds: Double

    func steps(stride: Double) -> Int {
        Int((distanceMeters / stride).rounded())
    }

    var minutes: Double { timeSeconds / 60 }
}

/// What the user is aiming for: a walking budget expressed either as minutes or
/// as a step count.
enum WalkTarget: Equatable {
    case minutes(Int)
    case steps(Int)

    /// Average walking pace, ~3 mph.
    static let metersPerSecond = 1.34
    /// Default stride length in meters (~0.76 m). Personalize later via HealthKit.
    static let defaultStride = 0.76

    /// Rough target distance, used only to size the initial station search and
    /// to pre-select candidate stops before precise walking routing.
    func approximateMeters(stride: Double = WalkTarget.defaultStride) -> Double {
        switch self {
        case .minutes(let m): return Double(m) * WalkTarget.metersPerSecond * 60
        case .steps(let s):   return Double(s) * stride
        }
    }

    /// How far a candidate walk is from the goal, in the goal's own unit
    /// (minutes or steps). Lower is a better match. This is what the
    /// get-off-early planner minimizes.
    func mismatch(for walk: WalkMeasure, stride: Double = WalkTarget.defaultStride) -> Double {
        switch self {
        case .minutes(let m): return abs(walk.minutes - Double(m))
        case .steps(let s):   return abs(Double(walk.steps(stride: stride)) - Double(s))
        }
    }
}
