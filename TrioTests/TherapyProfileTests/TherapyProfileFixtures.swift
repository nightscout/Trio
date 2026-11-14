import Foundation
@testable import Trio

enum TherapyProfileFixtures {
    static func profile(
        _ name: String,
        basal: [(Int, Double)] = [(0, 0.85), (21600, 1)],
        carbratio: [(Int, Double)] = [(0, 10)],
        sens: [(Int, Double)] = [(0, 50)],
        target: [(Int, Double, Double)] = [(0, 100, 110)]
    ) -> TrioTherapyProfile {
        TrioTherapyProfile(
            name: name,
            basal: basal.map { TherapyScheduleEntry(seconds: $0.0, value: decimal($0.1)) },
            carbRatio: carbratio.map { TherapyScheduleEntry(seconds: $0.0, value: decimal($0.1)) },
            sensitivity: sens.map { TherapyScheduleEntry(seconds: $0.0, value: decimal($0.1)) },
            target: target.map { TherapyTargetEntry(seconds: $0.0, low: decimal($0.1), high: decimal($0.2)) }
        )
    }

    /// The decimal the value reads as, without binary floating-point noise.
    static func decimal(_ value: Double) -> Decimal {
        Decimal(string: String(value)) ?? Decimal(value)
    }
}

extension TrioTherapyProfile {
    func withSensitivity(_ value: Decimal) -> TrioTherapyProfile {
        TrioTherapyProfile(
            name: name,
            basal: basal,
            carbRatio: carbRatio,
            sensitivity: [TherapyScheduleEntry(seconds: 0, value: value)],
            target: target
        )
    }
}
