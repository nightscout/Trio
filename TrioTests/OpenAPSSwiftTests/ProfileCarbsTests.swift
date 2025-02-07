import Foundation
import Testing
@testable import Trio

@Suite("Carb Ratio Profile") struct CarbRatioTests {
    let standardSchedule = CarbRatios(
        units: .grams,
        schedule: [
            CarbRatioEntry(start: "00:00:00", offset: 0, ratio: 15),
            CarbRatioEntry(start: "03:00:00", offset: 180, ratio: 18),
            CarbRatioEntry(start: "06:00:00", offset: 360, ratio: 20)
        ]
    )

    @Test("should return current carb ratio from schedule") func currentCarbRatio() async throws {
        let now = Calendar.current.date(from: DateComponents(year: 2025, month: 1, day: 26, hour: 2))!
        let ratio = Carbs.carbRatioLookup(carbRatio: standardSchedule, now: now)
        #expect(ratio == 15)
    }

    @Test("should handle ratio schedule changes") func handleScheduleChanges() async throws {
        let now = Calendar.current.date(from: DateComponents(year: 2025, month: 1, day: 26, hour: 4))!
        let ratio = Carbs.carbRatioLookup(carbRatio: standardSchedule, now: now)
        #expect(ratio == 18)
    }

    @Test("should handle exchanges unit conversion") func handleExchanges() async throws {
        let exchangeSchedule = CarbRatios(
            units: .exchanges,
            schedule: [
                CarbRatioEntry(start: "00:00:00", offset: 0, ratio: 12)
            ]
        )
        let ratio = Carbs.carbRatioLookup(carbRatio: exchangeSchedule)
        #expect(ratio == 1) // 12 grams per exchange
    }

    @Test("should reject invalid ratios") func rejectInvalidRatios() async throws {
        let invalidSchedule = CarbRatios(
            units: .grams,
            schedule: [
                CarbRatioEntry(start: "00:00:00", offset: 0, ratio: 2),
                CarbRatioEntry(start: "03:00:00", offset: 180, ratio: 15)
            ]
        )
        let now = Calendar.current.date(from: DateComponents(year: 2025, month: 1, day: 26, hour: 2))!
        var ratio = Carbs.carbRatioLookup(carbRatio: invalidSchedule, now: now)
        #expect(ratio == nil)

        let invalidSchedule2 = CarbRatios(
            units: .grams,
            schedule: [
                CarbRatioEntry(start: "00:00:00", offset: 0, ratio: 200)
            ]
        )

        ratio = Carbs.carbRatioLookup(carbRatio: invalidSchedule2, now: now)
        #expect(ratio == nil)
    }
}
