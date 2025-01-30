import Foundation

enum JSONValue: Codable {
    case string(String)
    case number(Double)
    case boolean(Bool)
    case array([JSONValue])
    case object([String: JSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
            return
        }

        if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else if let boolean = try? container.decode(Bool.self) {
            self = .boolean(boolean)
        } else if let array = try? container.decode([JSONValue].self) {
            self = .array(array)
        } else if let object = try? container.decode([String: JSONValue].self) {
            self = .object(object)
        } else {
            throw DecodingError.typeMismatch(JSONValue.self, DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "Invalid JSON value"
            ))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value): try container.encode(value)
        case let .number(value): try container.encode(value)
        case let .boolean(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case let .object(value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

public struct ValueDifference: Codable {
    let js: JSONValue
    let native: JSONValue
    let jsKeyMissing: Bool
    let nativeKeyMissing: Bool
}

public enum JSONCompare {
    public static func logDifferences(
        label: String,
        native: String,
        nativeRuntime: TimeInterval,
        javascript: String,
        javascriptRuntime: TimeInterval
    ) {
        guard let differences = try? differences(native: native, javascript: javascript) else {
            warning(.openAPS, "Exception calculating differences")
            return
        }

        // TODO: For now we'll just print this out to the console but we'll add proper logging next
        debug(.openAPS, "\(label) -> n: \(nativeRuntime)s, js: \(javascriptRuntime)s")
        prettyPrint(differences)
    }

    public static func prettyPrint(_ differences: [String: ValueDifference]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        if let data = try? encoder.encode(differences),
           let prettyString = String(data: data, encoding: .utf8)
        {
            debug(.openAPS, prettyString)
        }
    }

    public static func differences(native: String, javascript: String) throws -> [String: ValueDifference] {
        guard let jsData = javascript.data(using: .utf8),
              let nativeData = native.data(using: .utf8),
              let jsDict = try JSONSerialization.jsonObject(with: jsData) as? [String: Any],
              let nativeDict = try JSONSerialization.jsonObject(with: nativeData) as? [String: Any]
        else {
            throw NSError(domain: "JSONBridge", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON format"])
        }

        var differences: [String: ValueDifference] = [:]

        // Check all keys present in either dictionary
        Set(jsDict.keys).union(nativeDict.keys).forEach { key in
            let jsValue = jsDict[key].map(convertToJSONValue) ?? .null
            let nativeValue = nativeDict[key].map(convertToJSONValue) ?? .null

            if !valuesAreEqual(jsValue, nativeValue) {
                differences[key] = ValueDifference(
                    js: jsValue,
                    native: nativeValue,
                    jsKeyMissing: !jsDict.keys.contains(key),
                    nativeKeyMissing: !nativeDict.keys.contains(key)
                )
            }
        }

        return differences
    }

    private static func convertToJSONValue(_ value: Any) -> JSONValue {
        switch value {
        case let string as String:
            return .string(string)
        case let number as NSNumber:
            return .number(number.doubleValue)
        case let bool as Bool:
            return .boolean(bool)
        case let array as [Any]:
            return .array(array.map(convertToJSONValue))
        case let dict as [String: Any]:
            return .object(dict.mapValues(convertToJSONValue))
        case is NSNull:
            return .null
        default:
            return .null
        }
    }

    private static func valuesAreEqual(_ value1: JSONValue, _ value2: JSONValue) -> Bool {
        switch (value1, value2) {
        case (.null, .null):
            return true
        case let (.string(s1), .string(s2)):
            return s1 == s2
        case let (.number(n1), .number(n2)):
            return n1 == n2
        case let (.boolean(b1), .boolean(b2)):
            return b1 == b2
        case let (.array(a1), .array(a2)):
            return a1.count == a2.count && zip(a1, a2).allSatisfy(valuesAreEqual)
        case let (.object(o1), .object(o2)):
            return o1.keys == o2.keys && o1.keys.allSatisfy { key in
                guard let v1 = o1[key], let v2 = o2[key] else { return false }
                return valuesAreEqual(v1, v2)
            }
        default:
            return false
        }
    }
}
