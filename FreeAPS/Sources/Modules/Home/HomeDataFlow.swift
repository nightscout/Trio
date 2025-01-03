import Foundation
import LoopKitUI

enum Home {
    enum Config {}
}

protocol HomeProvider: Provider {
    func heartbeatNow()
    func pumpSettings() async -> PumpSettings
    func autotunedBasalProfile() async -> [BasalProfileEntry]
    func basalProfile() async -> [BasalProfileEntry]
    func tempTargets(hours: Int) -> [TempTarget]
    func pumpReservoir() async -> Decimal?
    func tempTarget() -> TempTarget?
    func getBGTargets() async -> BGTargets
}
