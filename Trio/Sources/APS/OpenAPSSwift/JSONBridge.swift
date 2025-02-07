import Foundation

enum JSONError: Error {
    case invalidString
    case decodingFailed(Error)
    case encodingFailed
}

enum JSONBridge {
    static func preferences(from: JSON) throws -> Preferences {
        try JSONBridge.from(string: from.rawJSON)
    }

    static func pumpSettings(from: JSON) throws -> PumpSettings {
        try JSONBridge.from(string: from.rawJSON)
    }

    static func bgTargets(from: JSON) throws -> BGTargets {
        try JSONBridge.from(string: from.rawJSON)
    }

    static func basalProfile(from: JSON) throws -> [BasalProfileEntry] {
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

    static func model(from: JSON) -> String {
        from.rawJSON
    }

    static func trioSettings(from: JSON) throws -> TrioSettings {
        try JSONBridge.from(string: from.rawJSON)
    }

    static func from<T: Decodable>(string: String) throws -> T {
        guard let data = string.data(using: .utf8) else {
            throw JSONError.invalidString
        }
        return try JSONCoding.decoder.decode(T.self, from: data)
    }

    static func to<T: Encodable>(_ value: T) throws -> String {
        let data = try JSONCoding.encoder.encode(value)
        guard let string = String(data: data, encoding: .utf8) else {
            throw JSONError.encodingFailed
        }
        return string
    }
}
