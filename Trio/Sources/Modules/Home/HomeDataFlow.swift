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
    }
}

protocol HomeProvider: Provider {
    func heartbeatNow()
    func pumpSettings() async -> PumpSettings
    func getBasalProfile() async -> [BasalProfileEntry]
    func pumpReservoir() async -> Decimal?
    func getBGTargets() async -> BGTargets
}
