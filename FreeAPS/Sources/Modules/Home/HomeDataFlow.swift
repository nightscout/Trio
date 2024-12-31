import Foundation
import LoopKitUI

enum Home {
    enum Config {}
}

protocol HomeProvider: Provider {
    func heartbeatNow()
    func pumpSettings() -> PumpSettings
    func getBasalProfile() async -> [BasalProfileEntry]
    func tempTargets(hours: Int) -> [TempTarget]
    func pumpReservoir() -> Decimal?
    func tempTarget() -> TempTarget?
    func getBGTarget() async -> BGTargets
}
