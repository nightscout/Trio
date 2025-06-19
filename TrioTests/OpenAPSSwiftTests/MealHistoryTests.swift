import Foundation
import Testing
@testable import Trio

@Suite("MealHistory Tests") struct MealHistoryTests {
    @Test("should process carbs from carbHistory") func processCarbsFromCarbHistory() async {
        let carbHistory = [
            CarbsEntry.forTest(
                createdAt: Date.from(isoString: "2016-06-19T12:00:00-04:00"),
                carbs: 20
            )
        ]

        let output = MealHistory.findMealInputs(
            pumpHistory: [],
            carbHistory: carbHistory
        )

        #expect(output.count == 1)
        #expect(output[0].carbs == 20)
        #expect(output[0].timestamp == Date.from(isoString: "2016-06-19T12:00:00-04:00"))
    }

    @Test("should process bolus events from pumpHistory") func processBolusEventsFromPumpHistory() async {
        let pumpHistory = [
            PumpHistoryEvent(
                id: UUID().uuidString,
                type: .bolus,
                timestamp: Date.from(isoString: "2016-06-19T12:00:00-04:00"),
                amount: 2.5
            )
        ]

        let output = MealHistory.findMealInputs(
            pumpHistory: pumpHistory,
            carbHistory: []
        )

        #expect(output.count == 1)
        #expect(output[0].bolus == 2.5)
        #expect(output[0].timestamp == Date.from(isoString: "2016-06-19T12:00:00-04:00"))
    }

    @Test("should handle both carbs and bolus entries") func handleBothCarbsAndBolusEntries() async {
        let pumpHistory = [
            PumpHistoryEvent(
                id: UUID().uuidString,
                type: .bolus,
                timestamp: Date.from(isoString: "2016-06-19T12:00:00-04:00"),
                amount: 2.5
            )
        ]

        let carbHistory = [
            CarbsEntry.forTest(
                createdAt: Date.from(isoString: "2016-06-19T12:30:00-04:00"),
                carbs: 20
            )
        ]

        let output = MealHistory.findMealInputs(
            pumpHistory: pumpHistory,
            carbHistory: carbHistory
        )

        #expect(output.count == 2)

        // Find the carb entry
        let carbEntry = output.first { $0.carbs != nil }
        #expect(carbEntry != nil)
        #expect(carbEntry?.carbs == 20)

        // Find the bolus entry
        let bolusEntry = output.first { $0.bolus != nil }
        #expect(bolusEntry != nil)
        #expect(bolusEntry?.bolus == 2.5)
    }

    @Test("should dedupe carb entries with same timestamp") func dedupeCarbs() async {
        let carbHistory = [
            CarbsEntry.forTest(
                createdAt: Date.from(isoString: "2016-06-19T12:00:00-04:00"),
                carbs: 20
            ),
            CarbsEntry.forTest(
                createdAt: Date.from(isoString: "2016-06-19T12:00:00-04:00"),
                carbs: 30
            )
        ]

        let output = MealHistory.findMealInputs(
            pumpHistory: [],
            carbHistory: carbHistory
        )

        #expect(output.count == 1)
        #expect(output[0].carbs == 20)
    }

    @Test("should dedupe bolus entries with same timestamp") func dedupeBolusEntries() async {
        let pumpHistory = [
            PumpHistoryEvent(
                id: UUID().uuidString,
                type: .bolus,
                timestamp: Date.from(isoString: "2016-06-19T12:00:00-04:00"),
                amount: 2.5
            ),
            PumpHistoryEvent(
                id: UUID().uuidString,
                type: .bolus,
                timestamp: Date.from(isoString: "2016-06-19T12:00:00-04:00"),
                amount: 3.0
            )
        ]

        let output = MealHistory.findMealInputs(
            pumpHistory: pumpHistory,
            carbHistory: []
        )

        #expect(output.count == 1)
        #expect(output[0].bolus == 2.5)
    }

    @Test("should consider timestamps within 2 seconds as duplicates") func timestampNearlyDuplicates() async {
        let pumpHistory = [
            PumpHistoryEvent(
                id: UUID().uuidString,
                type: .bolus,
                timestamp: Date.from(isoString: "2016-06-19T12:00:00-04:00"),
                amount: 2.5
            ),
            PumpHistoryEvent(
                id: UUID().uuidString,
                type: .bolus,
                timestamp: Date.from(isoString: "2016-06-19T12:00:01-04:00"),
                amount: 3.0
            )
        ]

        let output = MealHistory.findMealInputs(
            pumpHistory: pumpHistory,
            carbHistory: []
        )

        #expect(output.count == 1)
        #expect(output[0].bolus == 2.5)
    }
}
