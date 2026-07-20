import Foundation

enum JSONError: Error {
    case invalidString
    case invalidDate(String)
    case decodingFailed(Error)
    case encodingFailed
}

enum JSONBridge {
    static func pumpSettings(from: JSON) throws -> PumpSettings {
        try JSONBridge.from(string: from.rawJSON)
    }

    static func bgTargets(from: JSON) throws -> BGTargets {
        try JSONBridge.from(string: from.rawJSON)
    }

    static func basalProfile(from: JSON) throws -> [BasalProfileEntry] {
        try JSONBridge.from(string: from.rawJSON)
    }

    static func trioCustomOrefVariables(from: JSON) throws -> TrioCustomOrefVariables {
        try JSONBridge.from(string: from.rawJSON)
    }

    static func insulinSensitivities(from: JSON) throws -> InsulinSensitivities {
        try JSONBridge.from(string: from.rawJSON)
    }

    static func carbRatios(from: JSON) throws -> CarbRatios {
        try JSONBridge.from(string: from.rawJSON)
    }

    static func tempTargets(from: JSON) throws -> [TempTarget] {
        try JSONBridge.from(string: from.rawJSON)
    }

    static func profile(from: JSON) throws -> Profile {
        try JSONBridge.from(string: from.rawJSON)
    }

    static func autosens(from: JSON) throws -> Autosens? {
        try JSONBridge.from(string: from.rawJSON)
    }

    static func from<T: Decodable>(string: String) throws -> T {
        guard let data = string.data(using: .utf8) else {
            throw JSONError.invalidString
        }
        return try JSONCoding.decoder.decode(T.self, from: data)
    }
}
