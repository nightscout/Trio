import Foundation
import LoopKitUI

enum Home {
    enum Config {}

    /// Result of enacting a Quick-Pick Treatment. `nil` means that part wasn't requested.
    struct QuickPickTreatmentOutcome {
        enum ActionResult {
            case succeeded
            case failed
        }

        var carbsResult: ActionResult?
        var bolusResult: ActionResult?
        /// Set when `bolusResult == .failed` and the pump itself reported why (e.g. busy). `nil` means
        /// the failure was at authentication, before the pump was ever asked to enact anything.
        var bolusFailureMessage: String?
    }
}

protocol HomeProvider: Provider {
    func heartbeatNow()
    func pumpSettings() async -> PumpSettings
    func getBasalProfile() async -> [BasalProfileEntry]
    func pumpReservoir() async -> Decimal?
    func getBGTargets() async -> BGTargets
}
