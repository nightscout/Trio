import Foundation
import LibreTransmitter
import LoopKit

extension BloodGlucose.Direction {
    init(trend: Int) {
        guard trend < Int(Int8.max) else {
            self = .none
            return
        }

        switch trend {
        case let x where x <= -30:
            self = .doubleDown
        case let x where x <= -20:
            self = .singleDown
        case let x where x <= -10:
            self = .fortyFiveDown
        case let x where x < 10:
            self = .flat
        case let x where x < 20:
            self = .fortyFiveUp
        case let x where x < 30:
            self = .singleUp
        default:
            self = .doubleUp
        }
    }

    init(trendType: LoopKit.GlucoseTrend?) {
        switch trendType {
        case .upUpUp:
            self = .doubleUp
        case .upUp:
            self = .singleUp
        case .up:
            self = .fortyFiveUp
        case .flat:
            self = .flat
        case .down:
            self = .fortyFiveDown
        case .downDown:
            self = .singleDown
        case .downDownDown:
            self = .doubleDown
        default:
            self = .none
        }
    }
}
