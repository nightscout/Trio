import Foundation
import OrefAlgorithm

/// The smallest consumer of this package: a plain `import OrefAlgorithm` with no `@testable`
/// and no module alias, calling a few public symbols. This is the import path every other
/// project uses, so `OrefAlgorithmExampleTests` drives it under `swift test` and CI fails if
/// it ever breaks. Run it directly with `swift run --package-path AlgorithmPackage OrefAlgorithmExample`.
@main enum ExampleConsumer {
    /// Minutes from delivery to peak activity for the ultra-rapid curve with default settings.
    static func ultraRapidPeakMinutes() -> Double? {
        IobCalculation.lookupPeak(curve: .ultraRapid, useCustomPeakTime: false, insulinPeakTime: 55)
    }

    /// Two suspends at one timestamp collapse to one; the resume and the bolus survive.
    static func dedupedEventCount() -> Int {
        let at = Date(timeIntervalSince1970: 1_700_000_000)
        let history = [
            PumpHistoryEvent(id: "s-1", type: .pumpSuspend, timestamp: at),
            PumpHistoryEvent(id: "s-2", type: .pumpSuspend, timestamp: at),
            PumpHistoryEvent(id: "r-1", type: .pumpResume, timestamp: at + 600),
            PumpHistoryEvent(id: "b-1", type: .bolus, timestamp: at + 1200, amount: 1)
        ]
        return history.removingDuplicateSuspendResumeEvents().count
    }

    /// The Double boundary round-trips a pump rate without losing an increment.
    static func roundTrippedRate(_ rate: Double) -> Double {
        Decimal(algorithmValue: rate).nearestDouble
    }

    static func main() {
        guard let peak = ultraRapidPeakMinutes() else {
            print("lookupPeak returned nil")
            return
        }
        print("Ultra-rapid insulin peaks \(peak) minutes after delivery")
    }
}
