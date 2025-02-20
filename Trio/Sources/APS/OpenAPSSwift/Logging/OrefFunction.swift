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
    case makeProfile

    // since we're removing some keys from our Profile that exist in Javascript
    // we need to let the difference function know which keys to ignore when
    // calculating differences
    func keysToIgnore() -> Set<String> {
        switch self {
        case .makeProfile:
            return Set(["calc_glucose_noise", "enableEnliteBgproxy", "exercise_mode", "offline_hotspot"])
        }
    }
}
