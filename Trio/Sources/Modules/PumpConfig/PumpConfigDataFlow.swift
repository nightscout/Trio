import Combine
import LoopKit
import LoopKitUI

enum PumpConfig {
    enum Config {}

    enum PumpType: Equatable {
        case minimed
        case omnipod
        case omnipodBLE
        case dana
        case simulator
    }

    struct PumpInitialSettings {
        let maxBolusUnits: Double
        let maxBasalRateUnitsPerHour: Double
        let basalSchedule: BasalRateSchedule

        static let `default` = PumpInitialSettings(
            maxBolusUnits: 10,
            maxBasalRateUnitsPerHour: 2,
            basalSchedule: BasalRateSchedule(dailyItems: [RepeatingScheduleValue(startTime: 0, value: 1.0)])!
        )
    }
}

struct PumpDisplayState {
    let name: String
    let image: UIImage?
}

protocol PumpConfigProvider: Provider {
    func setPumpManager(_: PumpManagerUI)
    var pumpDisplayState: AnyPublisher<PumpDisplayState?, Never> { get }
    func pumpSettings() -> PumpSettings
    func getBasalProfile() async -> [BasalProfileEntry]
}
