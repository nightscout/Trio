import Foundation

/// After the port from Javascript to Swift is complete, we should remove the logging module:
/// https://github.com/nightscout/Trio-dev/issues/293

enum OrefFunctionResult {
    case success(RawJSON)
    case failure(Error)

    func returnOrThrow() throws -> RawJSON {
        switch self {
        case let .success(json): return json
        case let .failure(error): throw error
        }
    }
}

enum OrefFunction: String, Codable {
    enum ReturnType {
        case array
        case dictionary
    }

    case autosens
    case iob
    case meal
    case makeProfile
    case determineBasal

    // since we're removing some keys from our Profile that exist in Javascript
    // we need to let the difference function know which keys to ignore when
    // calculating differences
    func keysToIgnore() -> Set<String> {
        switch self {
        case .makeProfile:
            return Set(["calc_glucose_noise", "enableEnliteBgproxy", "exercise_mode", "offline_hotspot"])
        case .iob:
            return Set()
        case .meal:
            // These aren't used by downstream calculations, so we
            // can ignore them in our comparison
            return Set(["maxDeviation", "minDeviation", "allDeviations", "bwCarbs", "bwFound", "journalCarbs", "nsCarbs"])
        case .autosens:
            return Set(["deviationsUnsorted", "debugInfo"])
        case .determineBasal:
            // We ignore some properties that aren't used downstream
            return Set([
                // Not used, ignore
                "id",
                "temp",
                "reservoir",
                "ISF",
                "TDD",
                "minDelta",
                "received",
                // intentionally removed from Swift, but in JS
                "insulinForManualBolus",
                "manualBolusErrorString",
                // in JS but not in Swift
                "tick",
                "BGI",
                "target_bg",
                "deviation",
                // in Swift but not in JS
                "timestamp",
                "minGuardBG",
                "minPredBG"
            ])
        }
    }

    // Some values might be slightly different due to Double vs Decimal
    // and minor algorithmic differences
    func approximateMatchingNumbers() -> [String: Double] {
        switch self {
        case .makeProfile:
            return [:]
        case .iob:
            // for iob we can get rounding errors because of Double vs Decimal
            // so we leave a little extra room for our comparisons
            return [
                "iob": 0.1,
                "activity": 0.01,
                "basaliob": 0.25,
                "bolusiob": 0.25,
                "netbasalinsulin": 0.25,
                "bolusinsulin": 0.25
            ]
        case .meal:
            return [
                "carbs": 0.1,
                "mealCOB": 10,
                "currentDeviation": 1,
                "slopeFromMaxDeviation": 0.25,
                "slopeFromMinDeviation": 0.25,
                "lastCarbTime": 1
            ]
        case .autosens:
            return [
                "ratio": 0.021,
                "newisf": 3.1
            ]
        case .determineBasal:
            return [
                "sensitivityRatio": 0.011,
                "expectedDelta": 0.11,
                "eventualBG": 1.1,
                "IOB": 1.1,
                "ZT": 1.1,
                "UAM": 1.1,
                "COB": 1.1
            ]
        }
    }

    func returnType() -> ReturnType {
        switch self {
        case .makeProfile:
            return .dictionary
        case .iob:
            return .array
        case .meal:
            return .dictionary
        case .autosens:
            return .dictionary
        case .determineBasal:
            return .dictionary
        }
    }

    func flexibleArrayKeys() -> [String] {
        switch self {
        case .determineBasal:
            return ["predBGs.UAM", "predBGs.COB", "predBGs.ZT", "predBGs.IOB"]
        default:
            return []
        }
    }

    /// Properties to skip during object comparison. Unlike keysToIgnore which filters
    /// final differences, this skips properties during the recursive comparison itself.
    /// This is needed for array return types where differences are recorded at the
    /// element level rather than at individual property paths.
    func propertiesToSkip() -> Set<String> {
        switch self {
        case .iob:
            // Please see this issue for context on skipping lastTemp:
            // https://github.com/nightscout/Trio-dev/issues/453
            return Set(["lastTemp"])
        default:
            return Set()
        }
    }
}
