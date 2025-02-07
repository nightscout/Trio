import Foundation
import Testing
@testable import Trio

@Suite("ISF Profile") struct ISFTests {
    let standardISF = InsulinSensitivities(
        units: .mgdL,
        userPreferredUnits: .mgdL,
        sensitivities: [
            InsulinSensitivityEntry(sensitivity: 100, offset: 0, start: "00:00:00"),
            InsulinSensitivityEntry(sensitivity: 80, offset: 180, start: "03:00:00"),
            InsulinSensitivityEntry(sensitivity: 90, offset: 360, start: "06:00:00")
        ]
    )

    @Test("should return current insulin sensitivity factor from schedule") func currentISF() async throws {
        let now = Calendar.current.date(from: DateComponents(year: 2025, month: 1, day: 26, hour: 2))!
        let (sensitivity, _) = try Isf.isfLookup(isfDataInput: standardISF, timestamp: now)
        #expect(sensitivity == 100)
    }

    @Test("should handle sensitivity schedule changes") func handleScheduleChanges() async throws {
        let now = Calendar.current.date(from: DateComponents(year: 2025, month: 1, day: 26, hour: 4))!
        let (sensitivity, _) = try Isf.isfLookup(isfDataInput: standardISF, timestamp: now)
        #expect(sensitivity == 80)
    }

    @Test("should use last sensitivity if past schedule end") func useLastSensitivity() async throws {
        let now = Calendar.current.date(from: DateComponents(year: 2025, month: 1, day: 26, hour: 23))!
        let (sensitivity, _) = try Isf.isfLookup(isfDataInput: standardISF, timestamp: now)
        #expect(sensitivity == 90)
    }

    @Test("should produce the same result without a cache") func cacheLastResult() async throws {
        let now = Calendar.current.date(from: DateComponents(year: 2025, month: 1, day: 26, hour: 4, minute: 30))!
        let (sensitivity1, _) = try Isf.isfLookup(isfDataInput: standardISF, timestamp: now)
        let (sensitivity2, _) = try Isf.isfLookup(isfDataInput: standardISF, timestamp: now)
        #expect(sensitivity1 == sensitivity2)
        #expect(sensitivity1 == 80)
    }

    @Test("should provide updated inputs with the `endOffset` parameter") func updatedInputs() async throws {
        let now = Calendar.current.date(from: DateComponents(year: 2025, month: 1, day: 26, hour: 4))!
        let (sensitivity, isfUpdated) = try Isf.isfLookup(isfDataInput: standardISF, timestamp: now)
        #expect(sensitivity == 80)
        #expect(isfUpdated.sensitivities[0].endOffset == nil)
        #expect(isfUpdated.sensitivities[1].endOffset == 360)
        #expect(isfUpdated.sensitivities[2].endOffset == nil)
    }

    @Test("should return -1 for invalid profile with non-zero first offset") func handleInvalidProfile() async throws {
        let invalidISF = InsulinSensitivities(
            units: .mgdL,
            userPreferredUnits: .mgdL,
            sensitivities: [
                InsulinSensitivityEntry(sensitivity: 100, offset: 30, start: "00:30:00")
            ]
        )
        let (sensitivity, _) = try Isf.isfLookup(isfDataInput: invalidISF)
        #expect(sensitivity == -1)
    }
}
