import Foundation

enum ProfileError: LocalizedError, Equatable {
    case invalidDIA(value: Decimal)
    case invalidCurrentBasal(value: Decimal?)
    case invalidMaxDailyBasal(value: Decimal?)
    case invalidMaxBasal(value: Decimal?)
    case invalidISF(value: Decimal?)
    case invalidCarbRatio
    case invalidBgTargets
    case invalidCalendar

    var errorDescription: String? {
        switch self {
        case let .invalidDIA(value):
            return "DIA of \(String(describing: value)) is not supported (must be > 1)"
        case let .invalidCurrentBasal(value):
            return "Current basal of \(String(describing: value)) is not supported (must be > 0)"
        case let .invalidMaxDailyBasal(value):
            return "Max daily basal of \(String(describing: value)) is not supported (must be > 0)"
        case let .invalidMaxBasal(value):
            return "Max basal of \(String(describing: value)) is not supported (must be >= 0.1)"
        case let .invalidISF(value):
            return "ISF of \(String(describing: value)) is not supported (must be >= 5)"
        case .invalidCarbRatio:
            return "Profile wasn't given carb ratio data, cannot calculate carb_ratio"
        case .invalidBgTargets:
            return "Profile wasn't given bg target data"
        case .invalidCalendar:
            return "Unable to extract hours and minutes from the current calendar"
        }
    }
}
