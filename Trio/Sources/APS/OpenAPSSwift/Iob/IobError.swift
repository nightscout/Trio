import Foundation

enum IobError: LocalizedError, Equatable {
    case tempBasalDurationMismatch
    case tempBasalMissingDuration(timestamp: Date)
    case tempBasalDurationMissingDuration(timestamp: Date)
    case pumpSuspendResumeMismatch
    case basalRateNotSet
    case rateNotSetOnTempBasal(timestamp: Date)
    case bilinearCurveNotSupported
    case diaNotSet

    var errorDescription: String? {
        switch self {
        case .tempBasalDurationMismatch:
            return "Incomplete temp basal / duration pair"
        case let .tempBasalMissingDuration(timestamp):
            return "Temp basal is missing duration @ \(timestamp)"
        case let .tempBasalDurationMissingDuration(timestamp):
            return "Temp basal duration @ \(timestamp) pump history entry without a duration set"
        case .pumpSuspendResumeMismatch:
            return "Had two consecutive pump suspend or resume events"
        case .basalRateNotSet:
            return "Unable to derive the current basal rate from the profile data"
        case let .rateNotSetOnTempBasal(timestamp):
            return "Temp basal @ \(timestamp) without a rate set"
        case .bilinearCurveNotSupported:
            return "Bilinear curve not supported in Trio"
        case .diaNotSet:
            return "DIA not set on Profile"
        }
    }
}
