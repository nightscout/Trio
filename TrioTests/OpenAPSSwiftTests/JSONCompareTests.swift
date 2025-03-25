import Foundation
import Testing
@testable import Trio

@Suite("JSON Compare") struct JSONCompareTests {
    // Test fixtures
    let matchingJSON = """
    {
        "value": 42,
        "text": "hello",
        "flag": true,
        "nested": {
            "array": [1, 2, 3],
            "object": {"key": "value"}
        }
    }
    """

    @Test("should find no differences between identical JSONs") func matchingJSONs() async throws {
        let differences = try JSONCompare.differences(
            function: .makeProfile,
            swift: matchingJSON,
            javascript: matchingJSON
        )
        #expect(differences.isEmpty)
    }

    @Test("should detect scalar value differences") func scalarDifferences() async throws {
        let jsJSON = """
        {
            "number": 42,
            "text": "hello",
            "boolean": true
        }
        """

        let swiftJSON = """
        {
            "number": 43,
            "text": "world",
            "boolean": false
        }
        """

        let differences = try JSONCompare.differences(
            function: .makeProfile,
            swift: swiftJSON,
            javascript: jsJSON
        )

        #expect(differences.count == 3)
        #expect(differences["number"]?.js == .number(42))
        #expect(differences["number"]?.swift == .number(43))
        #expect(differences["text"]?.js == .string("hello"))
        #expect(differences["text"]?.swift == .string("world"))
        #expect(differences["boolean"]?.js == .boolean(true))
        #expect(differences["boolean"]?.swift == .boolean(false))
    }

    @Test("should detect missing keys") func missingKeys() async throws {
        let jsJSON = """
        {
            "common": 42,
            "jsOnly": "hello"
        }
        """

        let swiftJSON = """
        {
            "common": 42,
            "swiftOnly": "world"
        }
        """

        let differences = try JSONCompare.differences(
            function: .makeProfile,
            swift: swiftJSON,
            javascript: jsJSON
        )

        #expect(differences.count == 2)
        #expect(differences["jsOnly"]?.nativeKeyMissing == true)
        #expect(differences["jsOnly"]?.jsKeyMissing == false)
        #expect(differences["swiftOnly"]?.jsKeyMissing == true)
        #expect(differences["swiftOnly"]?.nativeKeyMissing == false)
    }

    @Test("should detect nested object differences") func nestedDifferences() async throws {
        let jsJSON = """
        {
            "nested": {
                "value": 42,
                "array": [1, 2, 3]
            }
        }
        """

        let swiftJSON = """
        {
            "nested": {
                "value": 43,
                "array": [1, 2, 4]
            }
        }
        """

        let differences = try JSONCompare.differences(
            function: .makeProfile,
            swift: swiftJSON,
            javascript: jsJSON
        )

        #expect(differences.count == 1)
        guard case let .object(nestedDiff) = differences["nested"]?.js else {
            throw TestFailure("Expected nested object difference")
        }
        #expect(nestedDiff["value"] == .number(42))
        #expect(nestedDiff["array"] == .array([.number(1), .number(2), .number(3)]))
    }

    @Test("should ignore specified keys for makeProfile") func keyIgnoring() async throws {
        let jsJSON = """
        {
            "value": 42,
            "calc_glucose_noise": true,
            "enableEnliteBgproxy": false
        }
        """

        let swiftJSON = """
        {
            "value": 42
        }
        """

        let differences = try JSONCompare.differences(
            function: .makeProfile,
            swift: swiftJSON,
            javascript: jsJSON
        )
        #expect(differences.isEmpty)
    }

    @Test("should handle invalid JSON") func invalidJSON() async throws {
        let invalidJSON = "{ invalid json }"

        do {
            _ = try JSONCompare.differences(
                function: .makeProfile,
                swift: invalidJSON,
                javascript: matchingJSON
            )
            throw TestFailure("Expected error for invalid JSON")
        } catch {
            // Expected error
            #expect(true)
        }
    }

    @Test("should handle empty JSON objects") func emptyObjects() async throws {
        let emptyJSON = "{}"
        let differences = try JSONCompare.differences(
            function: .makeProfile,
            swift: emptyJSON,
            javascript: emptyJSON
        )
        #expect(differences.isEmpty)
    }

    @Test("should detect array length differences") func arrayLengthDifferences() async throws {
        let jsJSON = """
        {
            "array": [1, 2, 3]
        }
        """

        let swiftJSON = """
        {
            "array": [1, 2]
        }
        """

        let differences = try JSONCompare.differences(
            function: .makeProfile,
            swift: swiftJSON,
            javascript: jsJSON
        )

        #expect(differences.count == 1)
        guard case let .array(jsArray) = differences["array"]?.js,
              case let .array(swiftArray) = differences["array"]?.swift
        else {
            throw TestFailure("Expected array differences")
        }
        #expect(jsArray.count == 3)
        #expect(swiftArray.count == 2)
    }

    @Test("should be empty array for {} and [] pump history strings") func emptyPumpHistoryParsing() async throws {
        let emptyArray = try JSONBridge.pumpHistory(from: "[]")
        let emptyObject = try JSONBridge.pumpHistory(from: "{}")

        #expect(emptyArray.isEmpty)
        #expect(emptyObject.isEmpty)
    }
}

struct TestFailure: Error {
    let message: String

    init(_ message: String) {
        self.message = message
    }
}
