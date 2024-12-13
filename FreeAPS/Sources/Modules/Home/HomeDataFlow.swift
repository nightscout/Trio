import Foundation
import LoopKitUI

enum Home {
    enum Config {}
}

protocol HomeProvider: Provider {
    func heartbeatNow()
    func pumpSettings() -> PumpSettings
    func autotunedBasalProfile() -> [BasalProfileEntry]
    func basalProfile() -> [BasalProfileEntry]
    func tempTargets(hours: Int) -> [TempTarget]
    func pumpReservoir() -> Decimal?
    func tempTarget() -> TempTarget?
    func announcement(_ hours: Int) -> [Announcement]
    func getBGTarget() async -> BGTargets
}
