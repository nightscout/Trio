import Foundation

extension Preferences {
    /// Preferences as the algorithm should see them under `mode`. Derived, never persisted:
    /// the bolus calculator and `BolusSafetyValidator` read the same `maxIOB`.
    func clamped(for mode: DosingMode) -> Preferences {
        var clamped = self

        switch mode {
        case .closed,
             .open:
            return self

        case .lowGlucoseSuspend:
            // Max IOB 0 leaves oref's reduction stages intact and neuters correction and SMB.
            clamped.maxIOB = 0

        case .basalTesting:
            clamped.maxIOB = 0
            // Pin sensitivity so the test measures the profile the user entered, not an adapted one.
            clamped.autosensMin = 1
            clamped.autosensMax = 1
            clamped.useNewFormula = false
            clamped.sigmoid = false
            // Only step in for a genuine low; the picker allows 60...120.
            clamped.threshold_setting = max(threshold_setting, Self.basalTestingThreshold)
        }

        return clamped
    }

    /// Glucose below which Basal Testing suspends, in mg/dL.
    static let basalTestingThreshold: Decimal = 72
}
