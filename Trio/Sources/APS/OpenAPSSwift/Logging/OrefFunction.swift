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

    case makeProfile
    case iob

    // since we're removing some keys from our Profile that exist in Javascript
    // we need to let the difference function know which keys to ignore when
    // calculating differences
    func keysToIgnore() -> Set<String> {
        switch self {
        case .makeProfile:
            return Set(["calc_glucose_noise", "enableEnliteBgproxy", "exercise_mode", "offline_hotspot"])
        case .iob:
            // we're only checking the first result for now
            return Set(stride(from: 1, to: 48, by: 1).map { String("[\($0)]") })
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
                "bolusinsulin": 0.25,
                "duration": 0.1
            ]
        }
    }

    func returnType() -> ReturnType {
        switch self {
        case .makeProfile:
            return .dictionary
        case .iob:
            return .array
        }
    }
}
