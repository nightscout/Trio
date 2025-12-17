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
        javascriptDuration: TimeInterval,
        iobInputs: IobInputs? = nil,
        mealInputs: MealInputs? = nil,
        autosensInputs: AutosensInputs? = nil,
        determineBasalInputs: DetermineBasalInputs? = nil
    ) {
        let comparison = createComparison(
            function: function,
            swift: swift,
            swiftDuration: swiftDuration,
            javascript: javascript,
            javascriptDuration: javascriptDuration,
            iobInputs: iobInputs,
            mealInputs: mealInputs,
            autosensInputs: autosensInputs,
            determineBasalInputs: determineBasalInputs
        )

        Task {
            do {
                try await log?.logComparison(comparison: comparison)
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
        javascriptDuration: TimeInterval,
        iobInputs: IobInputs?,
        mealInputs: MealInputs?,
        autosensInputs: AutosensInputs?,
        determineBasalInputs: DetermineBasalInputs?
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
                    differences: differences.isEmpty ? nil : differences,
                    iobInputs: differences.isEmpty ? nil : iobInputs,
                    mealInputs: differences.isEmpty ? nil : mealInputs,
                    autosensInputs: differences.isEmpty ? nil : autosensInputs,
                    determineBasalInputs: differences.isEmpty ? nil : determineBasalInputs
                )
            } catch {
                return AlgorithmComparison(
                    function: function,
                    resultType: .comparisonError,
                    jsDuration: javascriptDuration,
                    swiftDuration: swiftDuration,
                    comparisonError: AlgorithmException(error: error),
                    iobInputs: iobInputs,
                    mealInputs: mealInputs,
                    autosensInputs: autosensInputs,
                    determineBasalInputs: determineBasalInputs
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
                swiftException: AlgorithmException(error: swiftError),
                iobInputs: iobInputs,
                mealInputs: mealInputs,
                autosensInputs: autosensInputs,
                determineBasalInputs: determineBasalInputs
            )

        case let (.success, .failure(jsError)):
            return AlgorithmComparison(
                function: function,
                resultType: .jsOnlyException,
                swiftDuration: swiftDuration,
                jsException: AlgorithmException(error: jsError),
                iobInputs: iobInputs,
                mealInputs: mealInputs,
                autosensInputs: autosensInputs,
                determineBasalInputs: determineBasalInputs
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

    static func differences(function: OrefFunction, swift: String, javascript: String) throws -> [String: ValueDifference] {
        let differences = try {
            switch function.returnType() {
            case .array:
                return try differencesArray(function: function, swift: swift, javascript: javascript)
            case .dictionary:
                return try differencesDictionary(function: function, swift: swift, javascript: javascript)
            }
        }()

        let keysToIgnore = function.keysToIgnore()
        return differences.filter { !keysToIgnore.contains($0.key) }
    }

    private static func differencesArray(
        function: OrefFunction,
        swift: String,
        javascript: String
    ) throws -> [String: ValueDifference] {
        guard let jsData = javascript.data(using: .utf8),
              let swiftData = swift.data(using: .utf8),
              let jsArray = try JSONSerialization.jsonObject(with: jsData) as? [Any],
              let swiftArray = try JSONSerialization.jsonObject(with: swiftData) as? [Any]
        else {
            throw NSError(domain: "JSONBridge", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON format"])
        }

        // Converting arrays into dictionaries for comparison
        let jsDict = Dictionary(uniqueKeysWithValues: jsArray.enumerated().map { index, value in
            ("[\(index)]", value)
        })
        let swiftDict = Dictionary(uniqueKeysWithValues: swiftArray.enumerated().map { index, value in
            ("[\(index)]", value)
        })

        return compareDict(function: function, swiftDict: swiftDict, jsDict: jsDict)
    }

    private static func differencesDictionary(
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

        return compareDict(function: function, swiftDict: swiftDict, jsDict: jsDict)
    }

    private static func compareDict(
        function: OrefFunction,
        swiftDict: [String: Any],
        jsDict: [String: Any],
        path: String = ""
    ) -> [String: ValueDifference] {
        var differences: [String: ValueDifference] = [:]
        let approximateKeys = function.approximateMatchingNumbers()
        let flexibleArrayKeys = function.flexibleArrayKeys()
        let propertiesToSkip = function.propertiesToSkip()

        // Check all keys present in either dictionary
        Set(jsDict.keys).union(swiftDict.keys).forEach { key in
            let currentPath = path.isEmpty ? key : "\(path).\(key)"
            let jsValue = jsDict[key].map(convertToJSONValue) ?? .null
            let swiftValue = swiftDict[key].map(convertToJSONValue) ?? .null

            if !valuesAreEqual(
                jsValue, swiftValue,
                approximately: approximateKeys[key],
                approximateKeys: approximateKeys,
                flexibleArrayKeys: flexibleArrayKeys,
                propertiesToSkip: propertiesToSkip,
                currentPath: currentPath
            ) {
                differences[currentPath] = ValueDifference(
                    js: jsValue,
                    swift: swiftValue,
                    jsKeyMissing: !jsDict.keys.contains(key),
                    nativeKeyMissing: !swiftDict.keys.contains(key)
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

    private static func valuesAreEqual(
        _ value1: JSONValue,
        _ value2: JSONValue,
        approximately: Double?,
        approximateKeys: [String: Double],
        flexibleArrayKeys: [String],
        propertiesToSkip: Set<String>,
        currentPath: String
    ) -> Bool {
        switch (value1, value2) {
        case (.null, .null):
            return true
        case let (.string(s1), .string(s2)):
            return s1 == s2
        case let (.string(s1), .number(n2)):
            guard let n1 = Double(s1) else { return false }
            return n1.isApproximatelyEqual(to: n2, epsilon: approximately)
        case let (.number(n1), .string(s2)):
            guard let n2 = Double(s2) else { return false }
            return n1.isApproximatelyEqual(to: n2, epsilon: approximately)
        case let (.number(n1), .number(n2)):
            let match = n1.isApproximatelyEqual(to: n2, epsilon: approximately)
            return match
        case let (.boolean(b1), .boolean(b2)):
            return b1 == b2
        case let (.array(a1), .array(a2)):
            if flexibleArrayKeys.contains(currentPath), !a1.isEmpty, !a2.isEmpty {
                let shortestCount = min(a1.count, a2.count)
                return zip(a1.prefix(shortestCount), a2.prefix(shortestCount)).allSatisfy { v1, v2 in
                    valuesAreEqual(
                        v1, v2, approximately: approximately, approximateKeys: approximateKeys,
                        flexibleArrayKeys: flexibleArrayKeys, propertiesToSkip: propertiesToSkip,
                        currentPath: currentPath
                    )
                }
            }
            return a1.count == a2.count && zip(a1, a2).allSatisfy { v1, v2 in
                valuesAreEqual(
                    v1, v2, approximately: approximately, approximateKeys: approximateKeys,
                    flexibleArrayKeys: flexibleArrayKeys, propertiesToSkip: propertiesToSkip,
                    currentPath: currentPath
                )
            }
        case let (.object(o1), .object(o2)):
            // Filter out properties that should be skipped during comparison
            let keys1 = Set(o1.keys).subtracting(propertiesToSkip)
            let keys2 = Set(o2.keys).subtracting(propertiesToSkip)
            return keys1 == keys2 && keys1.allSatisfy { key in
                guard let v1 = o1[key], let v2 = o2[key] else { return false }
                return valuesAreEqual(
                    v1, v2, approximately: approximateKeys[key], approximateKeys: approximateKeys,
                    flexibleArrayKeys: flexibleArrayKeys, propertiesToSkip: propertiesToSkip,
                    currentPath: "\(currentPath).\(key)"
                )
            }
        default:
            return false
        }
    }
}
