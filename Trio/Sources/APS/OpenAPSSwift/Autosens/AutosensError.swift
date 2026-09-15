import Foundation

enum AutosensError: LocalizedError, Equatable {
    case missingIsfProfile
    case missingCarbRatioInProfile
    case missingCurrentBasalInProfile
    case missingSensInProfile
    case missingMaxDailyBasalInProfile
    case isfLookupError

    var errorDescription: String? {
        switch self {
        case .missingIsfProfile:
            return "No ISF set on the profile"
        case .missingCarbRatioInProfile:
            return "Carb ratio is not set on the profile"
        case .missingCurrentBasalInProfile:
            return "Current basal is not set on the profile"
        case .missingSensInProfile:
            return "Sensitivity is not set on the profile"
        case .missingMaxDailyBasalInProfile:
            return "Max Daily Basal is not set on the profile"
        case .isfLookupError:
            return "Unable to lookup the ISF"
        }
    }
}
