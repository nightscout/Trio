import Foundation

enum ConfirmBolus: String, JSON, CaseIterable, Identifiable, Codable, Hashable {
    var id: String { rawValue }
    case never
    case veryLowGlucose
    case veryLowForecast
    case always
    var displayName: String {
        switch self {
        case .never:
            return String(localized: "Never", comment: "")

        case .veryLowGlucose:
            return String(localized: "Very Low Glucose", comment: "")

        case .veryLowForecast:
            return String(localized: "Very Low Forecast", comment: "")

        case .always:
            return String(localized: "Always", comment: "")
        }
    }
}
