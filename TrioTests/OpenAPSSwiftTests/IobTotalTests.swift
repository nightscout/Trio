import Foundation
import Testing
@testable import Trio

@Suite("Calculate Total IOB Tests") struct CalculateIobTotalTests {
    // Helper function to create a basic treatment
    func createTreatment(insulin: Decimal, timestamp: Date) -> ComputedPumpHistoryEvent {
        ComputedPumpHistoryEvent.forTest(
            type: .bolus,
            timestamp: timestamp,
            insulin: insulin
        )
    }

    // Helper function to create a basic profile
    func createProfile(
        dia: Decimal = 5,
        curve: InsulinCurve = .rapidActing,
        useCustomPeakTime: Bool = false,
        insulinPeakTime: Decimal = 0
    ) -> Profile {
        var profile = Profile()
        profile.curve = curve
        profile.useCustomPeakTime = useCustomPeakTime
        profile.insulinPeakTime = insulinPeakTime
        profile.dia = dia
        return profile
    }

    @Test("should return zero values when no treatments provided") func returnZeroForNoTreatments() async throws {
        let now = Date()
        let result = try IobCalculation.iobTotal(
            treatments: [],
            profile: createProfile(),
            time: now
        )

        #expect(result.iob == 0)
        #expect(result.activity == 0)
        #expect(result.basaliob == 0)
        #expect(result.bolusiob == 0)
    }

    @Test("should calculate total IOB with rapid-acting insulin bolus") func calculateTotalRapidActing() async throws {
        let now = Date()
        let thirtyMinsAgo = now - 30.minutesToSeconds
        let treatments = [createTreatment(insulin: 2, timestamp: thirtyMinsAgo)]

        let result = try IobCalculation.iobTotal(
            treatments: treatments,
            profile: createProfile(dia: 5, curve: .rapidActing),
            time: now
        )

        #expect(result.iob.isWithin(0.1, of: 1.8))
        #expect(result.bolusiob.isWithin(0.1, of: 1.8))
        #expect(result.basaliob == 0)
    }

    @Test("should calculate total IOB with ultra-rapid insulin bolus") func calculateTotalUltraRapid() async throws {
        let now = Date()
        let thirtyMinsAgo = now - 30.minutesToSeconds
        let treatments = [createTreatment(insulin: 2, timestamp: thirtyMinsAgo)]

        let result = try IobCalculation.iobTotal(
            treatments: treatments,
            profile: createProfile(dia: 5, curve: .ultraRapid),
            time: now
        )

        #expect(result.iob.isWithin(0.001, of: 1.769))
        #expect(result.bolusiob.isWithin(0.001, of: 1.769))
        #expect(result.basaliob == 0)
    }

    @Test("should calculate total IOB with basal insulin") func calculateTotalBasal() async throws {
        let now = Date()
        let thirtyMinsAgo = now - 30.minutesToSeconds
        let treatments = [createTreatment(insulin: -0.05, timestamp: thirtyMinsAgo)]

        let result = try IobCalculation.iobTotal(
            treatments: treatments,
            profile: createProfile(dia: 5, curve: .rapidActing),
            time: now
        )

        #expect(result.basaliob.isWithin(0.001, of: -0.046))
        #expect(result.bolusiob == 0)
    }

    @Test("should handle multiple treatments of different types") func handleMultipleTreatments() async throws {
        let now = Date()
        let treatments = [
            createTreatment(insulin: 2.0, timestamp: now - 30.minutesToSeconds),
            createTreatment(insulin: 0.05, timestamp: now - 20.minutesToSeconds),
            createTreatment(insulin: 1.0, timestamp: now - 10.minutesToSeconds)
        ]

        let result = try IobCalculation.iobTotal(
            treatments: treatments,
            profile: createProfile(dia: 5, curve: .rapidActing),
            time: now
        )

        #expect(result.basaliob.isWithin(0.001, of: 0.048))
        #expect(result.bolusinsulin == 3.0)
        #expect(result.netbasalinsulin == 0.05)
    }

    @Test("should handle custom peak times for rapid-acting insulin") func handleCustomPeakRapidActing() async throws {
        let now = Date()
        let thirtyMinsAgo = now - 30.minutesToSeconds
        let treatments = [createTreatment(insulin: 2.0, timestamp: thirtyMinsAgo)]

        let result = try IobCalculation.iobTotal(
            treatments: treatments,
            profile: createProfile(
                dia: 5,
                curve: .rapidActing,
                useCustomPeakTime: true,
                insulinPeakTime: 100
            ),
            time: now
        )

        #expect(result.iob.isWithin(0.001, of: 1.898))
    }

    @Test("should handle custom peak times for ultra-rapid insulin") func handleCustomPeakUltraRapid() async throws {
        let now = Date()
        let thirtyMinsAgo = now - 30.minutesToSeconds
        let treatments = [createTreatment(insulin: 2.0, timestamp: thirtyMinsAgo)]

        let result = try IobCalculation.iobTotal(
            treatments: treatments,
            profile: createProfile(
                dia: 5,
                curve: .ultraRapid,
                useCustomPeakTime: true,
                insulinPeakTime: 80
            ),
            time: now
        )

        #expect(result.iob.isWithin(0.001, of: 1.863))
    }

    @Test("should ignore future treatments") func ignoreFutureTreatments() async throws {
        let now = Date()
        let treatments = [
            createTreatment(insulin: 2.0, timestamp: now + 30.minutesToSeconds),
            createTreatment(insulin: 1.0, timestamp: now - 10.minutesToSeconds)
        ]

        let result = try IobCalculation.iobTotal(
            treatments: treatments,
            profile: createProfile(dia: 5, curve: .rapidActing),
            time: now
        )

        #expect(result.bolusinsulin == 1.0)
    }

    @Test("should ignore treatments older than DIA") func ignoreOldTreatments() async throws {
        let now = Date()
        let sixHoursAgo = now - 6.hoursToSeconds
        let treatments = [createTreatment(insulin: 2.0, timestamp: sixHoursAgo)]

        let result = try IobCalculation.iobTotal(
            treatments: treatments,
            profile: createProfile(dia: 5, curve: .rapidActing),
            time: now
        )

        #expect(result.iob == 0)
        #expect(result.activity == 0)
    }

    @Test("should enforce minimum DIA of 5 hours for both insulin types") func enforceMinimumDIA() async throws {
        let now = Date()
        let fourHoursAgo = now - 4.hoursToSeconds
        let treatments = [createTreatment(insulin: 2.0, timestamp: fourHoursAgo)]

        // Test rapid-acting
        let rapidResult = try IobCalculation.iobTotal(
            treatments: treatments,
            profile: createProfile(dia: 4, curve: .rapidActing),
            time: now
        )
        #expect(rapidResult.iob > 0)

        // Test ultra-rapid
        let ultraResult = try IobCalculation.iobTotal(
            treatments: treatments,
            profile: createProfile(dia: 4, curve: .ultraRapid),
            time: now
        )
        #expect(ultraResult.iob > 0)
    }
}
