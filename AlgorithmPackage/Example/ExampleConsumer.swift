import Foundation
import OrefAlgorithm

/// The smallest consumer of this package: a plain `import OrefAlgorithm` with no `@testable`
/// and no module alias, calling one public function. This is the import path every other
/// project uses, so `OrefAlgorithmExampleTests` drives it under `swift test` and CI fails if
/// it ever breaks. Run it directly with `swift run --package-path AlgorithmPackage OrefAlgorithmExample`.
@main enum ExampleConsumer {
    /// Minutes from delivery to peak activity for the ultra-rapid curve with default settings.
    static func ultraRapidPeakMinutes() -> Double? {
        IobCalculation.lookupPeak(curve: .ultraRapid, useCustomPeakTime: false, insulinPeakTime: 55)
    }

    static func main() {
        guard let peak = ultraRapidPeakMinutes() else {
            print("lookupPeak returned nil")
            return
        }
        print("Ultra-rapid insulin peaks \(peak) minutes after delivery")
    }
}
