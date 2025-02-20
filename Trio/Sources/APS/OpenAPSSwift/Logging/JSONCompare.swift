import Foundation

/// After the port from Javascript to Swift is complete, we should remove the logging module:
/// https://github.com/nightscout/Trio-dev/issues/293

enum JSONValue: Codable, Equatable {
    case string(String)
    case number(Double)
    case boolean(Bool)
    case array([JSONValue])
    case object([String: JSONValue])
    case null

    init(from decoder: Decoder) throws {
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

    func encode(to encoder: Encoder) throws {
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

    static func == (lhs: JSONValue, rhs: JSONValue) -> Bool {
        switch (lhs, rhs) {
        case (.null, .null):
            return true
        case let (.string(lhs), .string(rhs)):
            return lhs == rhs
        case let (.number(lhs), .number(rhs)):
            return lhs == rhs
        case let (.boolean(lhs), .boolean(rhs)):
            return lhs == rhs
        case let (.array(lhs), .array(rhs)):
            return lhs == rhs
        case let (.object(lhs), .object(rhs)):
            return lhs == rhs
        default:
            return false
        }
    }
}

struct ValueDifference: Codable {
    let js: JSONValue
    let swift: JSONValue
    let jsKeyMissing: Bool
    let nativeKeyMissing: Bool
}

enum JSONCompare {
    static let log = try? JsSwiftOrefComparisonLogger()
    static func logDifferences(
        function: OrefFunction,
        swift: OrefFunctionResult,
        swiftDuration: TimeInterval,
        javascript: OrefFunctionResult,
        javascriptDuration: TimeInterval
    ) {
        let comparison = createComparison(
            function: function,
            swift: swift,
            swiftDuration: swiftDuration,
            javascript: javascript,
            javascriptDuration: javascriptDuration
        )

        Task {
            do {
                try await log?.logComparison(comparison: comparison)
                debug(.openAPS, "\(function) -> n: \(swiftDuration)s, js: \(javascriptDuration)s")
                prettyPrint(comparison.differences ?? [:])
            } catch {
                warning(.openAPS, "logComparison exception: \(error)", error: error)
            }
        }
    }

    static func createComparison(
        function: OrefFunction,
        swift: OrefFunctionResult,
        swiftDuration: TimeInterval,
        javascript: OrefFunctionResult,
        javascriptDuration: TimeInterval
    ) -> AlgorithmComparison {
        switch (swift, javascript) {
        case let (.success(swiftJson), .success(javascriptJson)):
            do {
                let differences = try differences(function: function, swift: swiftJson, javascript: javascriptJson)
                let resultType: ComparisonResultType = differences.isEmpty ? .matching : .valueDifference
                return AlgorithmComparison(
                    function: function,
                    resultType: resultType,
                    jsDuration: javascriptDuration,
                    swiftDuration: swiftDuration,
                    differences: differences.isEmpty ? nil : differences
                )
            } catch {
                return AlgorithmComparison(
                    function: function,
                    resultType: .comparisonError,
                    jsDuration: javascriptDuration,
                    swiftDuration: swiftDuration,
                    comparisonError: AlgorithmException(error: error)
                )
            }

        case let (.failure(swiftError), .failure(jsError)):
            return AlgorithmComparison(
                function: function,
                resultType: .matchingExceptions,
                jsException: AlgorithmException(error: jsError),
                swiftException: AlgorithmException(error: swiftError)
            )

        case let (.failure(swiftError), .success):
            return AlgorithmComparison(
                function: function,
                resultType: .swiftOnlyException,
                jsDuration: javascriptDuration,
                swiftException: AlgorithmException(error: swiftError)
            )

        case let (.success, .failure(jsError)):
            return AlgorithmComparison(
                function: function,
                resultType: .jsOnlyException,
                swiftDuration: swiftDuration,
                jsException: AlgorithmException(error: jsError)
            )
        }
    }

    static func prettyPrint(_ differences: [String: ValueDifference]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        if let data = try? encoder.encode(differences),
           let prettyString = String(data: data, encoding: .utf8)
        {
            debug(.openAPS, prettyString)
        }
    }

    static func differences(
        function: OrefFunction,
        swift: String,
        javascript: String
    ) throws -> [String: ValueDifference] {
        guard let jsData = javascript.data(using: .utf8),
              let swiftData = swift.data(using: .utf8),
              let jsDict = try JSONSerialization.jsonObject(with: jsData) as? [String: Any],
              let swiftDict = try JSONSerialization.jsonObject(with: swiftData) as? [String: Any]
        else {
            throw NSError(domain: "JSONBridge", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON format"])
        }

        var differences: [String: ValueDifference] = [:]

        // Check all keys present in either dictionary
        Set(jsDict.keys).union(swiftDict.keys).forEach { key in
            let jsValue = jsDict[key].map(convertToJSONValue) ?? .null
            let swiftValue = swiftDict[key].map(convertToJSONValue) ?? .null

            if !valuesAreEqual(jsValue, swiftValue) {
                differences[key] = ValueDifference(
                    js: jsValue,
                    swift: swiftValue,
                    jsKeyMissing: !jsDict.keys.contains(key),
                    nativeKeyMissing: !swiftDict.keys.contains(key)
                )
            }
        }

        let keysToIgnore = function.keysToIgnore()
        return differences.filter { !keysToIgnore.contains($0.key) }
    }

    private static func convertToJSONValue(_ value: Any) -> JSONValue {
        switch value {
        case let string as String:
            return .string(string)
        case let number as NSNumber:
            // NSNumber can represent both booleans and numbers
            // Check if it's a boolean using the objCType
            let objCType = String(cString: number.objCType)
            if objCType == "c" || objCType == "B" { // These represent BOOLs in ObjC
                return .boolean(number.boolValue)
            } else {
                return .number(number.doubleValue)
            }
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
