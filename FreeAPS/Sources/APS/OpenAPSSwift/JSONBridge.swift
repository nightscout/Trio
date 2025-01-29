import Foundation
import OpenAPSKit

enum JSONError: Error {
    case invalidString
    case decodingFailed(Error)
    case encodingFailed
}

enum JSONBridge {
    static func preferences(from: JSON) throws -> OKPreferences {
        try JSONBridge.from(string: from.rawJSON)
    }

    static func pumpSettings(from: JSON) throws -> OKPumpSettings {
        try JSONBridge.from(string: from.rawJSON)
    }

    static func bgTargets(from: JSON) throws -> OKBGTargets {
        try JSONBridge.from(string: from.rawJSON)
    }

    static func basalProfile(from: JSON) throws -> [OKBasalProfileEntry] {
        try JSONBridge.from(string: from.rawJSON)
    }

    static func insulinSensitivities(from: JSON) throws -> OKInsulinSensitivities {
        try JSONBridge.from(string: from.rawJSON)
    }

    static func carbRatios(from: JSON) throws -> OKCarbRatios {
        try JSONBridge.from(string: from.rawJSON)
    }

    static func tempTargets(from: JSON) throws -> [OKTempTarget] {
        try JSONBridge.from(string: from.rawJSON)
    }

    static func model(from: JSON) -> String {
        from.rawJSON
    }

    static func autotune(from: JSON) throws -> OKAutotune? {
        guard from.rawJSON != RawJSON.null else { return nil }
        return try JSONBridge.from(string: from.rawJSON)
    }

    static func freeapsSettings(from: JSON) throws -> OKFreeAPSSettings {
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
