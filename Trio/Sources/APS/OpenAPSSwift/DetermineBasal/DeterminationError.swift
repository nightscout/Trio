import Foundation

enum DeterminationError: LocalizedError, Equatable {
    case missingGlucoseStatus
    case missingProfile
    case missingCurrentBasal
    case invalidProfileTarget
    case glucoseOutOfRange(glucose: Decimal)
    case cgmNoiseTooHigh(noise: Int)
    case noDelta
    case missingIob
    case missingInputs
    case eventualGlucoseCalculationError(sensitivity: Decimal, deviation: Decimal)
    case determinationError

    var errorDescription: String? {
        switch self {
        case .missingGlucoseStatus:
            return String(localized: "No glucose status; cannot determine basal.")
        case .missingProfile:
            return String(localized: "No profile; cannot determine basal.")
        case .missingCurrentBasal:
            // string copied from JS
            return String(localized: "Error: could not get current basal rate")
        case .invalidProfileTarget:
            // string copied from JS including trailing space
            return String(localized: "Error: could not determine target_bg. ")
        case let .glucoseOutOfRange(glucose):
            return String(localized: "Glucose out of range: \(glucose.description).")
        case let .cgmNoiseTooHigh(noise):
            return String(localized: "CGM noise level too high: \(noise).")
        case .noDelta:
            return String(localized: "No glucose delta (flat readings); cannot determine trend.")
        case .missingIob:
            return String(localized: "No IOB data available; cannot determine basal.")
        case .missingInputs:
            return String(localized: "Missing required inputs; cannot determine basal.")
        case let .eventualGlucoseCalculationError(sensitivity, deviation):
            return String(
                localized: "Could not calculate eventual glucose. Sensitivity: \(sensitivity.description), Deviation: \(deviation.description)"
            )
        case .determinationError:
            return String(localized: "Unknown determination error.")
        }
    }
}
