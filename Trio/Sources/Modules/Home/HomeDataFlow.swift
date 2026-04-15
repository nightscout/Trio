import Foundation
import LoopKitUI

enum Home {
    enum Config {}
}

protocol HomeProvider: Provider {
    func heartbeatNow()
    func pumpSettings() async -> PumpSettings
    func getBasalProfile() async -> [BasalProfileEntry]
    func pumpReservoir() async -> Decimal?
    func getBGTargets() async -> BGTargets
}
