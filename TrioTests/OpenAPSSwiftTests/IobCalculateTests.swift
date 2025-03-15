import Foundation
import Testing
@testable import Trio

@Suite("Calculate IOB Tests") struct CalculateIobTests {
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
        curve: InsulinCurve = .rapidActing,
        useCustomPeakTime: Bool = false,
        insulinPeakTime: Decimal = 0
    ) -> Profile {
        var profile = Profile()
        profile.curve = curve
        profile.useCustomPeakTime = useCustomPeakTime
        profile.insulinPeakTime = insulinPeakTime
        profile.dia = 3
        return profile
    }

    @Test("should return nil when treatment has no insulin") func returnNilForNoInsulin() async throws {
        let treatment = ComputedPumpHistoryEvent.forTest(
            type: .bolus,
            timestamp: Date()
        )

        let result = try IobCalculation.iobCalc(
            treatment: treatment,
            time: Date(),
            dia: 3,
            profile: createProfile()
        )

        #expect(result == nil)
    }

    @Test("should calculate IOB with default rapid-acting settings") func calculateDefaultRapidActing() async throws {
        let now = Date()
        let thirtyMinsAgo = now - 30.minutesToSeconds
        let treatment = createTreatment(insulin: 2, timestamp: thirtyMinsAgo)

        let result = try IobCalculation.iobCalc(
            treatment: treatment,
            time: now,
            dia: 3,
            profile: createProfile()
        )

        #expect(result != nil)
        #expect(result!.activityContrib.isWithin(0.0001, of: 0.0115))
        #expect(result!.iobContrib.isWithin(0.0001, of: 1.8085))
    }

    @Test("should calculate IOB with custom peak time for rapid-acting insulin") func calculateCustomPeakRapidActing() async throws {
        let now = Date()
        let thirtyMinsAgo = now - 30.minutesToSeconds
        let treatment = createTreatment(insulin: 2, timestamp: thirtyMinsAgo)

        let profile = createProfile(
            curve: .rapidActing,
            useCustomPeakTime: true,
            insulinPeakTime: 100
        )

        let result = try IobCalculation.iobCalc(
            treatment: treatment,
            time: now,
            dia: 3,
            profile: profile
        )

        #expect(result != nil)
        #expect(result!.activityContrib.isWithin(0.0001, of: 0.0079))
        #expect(result!.iobContrib.isWithin(0.0001, of: 1.8763))
    }

    @Test("should handle peak time limits for rapid-acting insulin") func handlePeakTimeLimitsRapidActing() async throws {
        let now = Date()
        let thirtyMinsAgo = now - 30.minutesToSeconds
        let treatment = createTreatment(insulin: 2, timestamp: thirtyMinsAgo)

        // Test upper limit (120)
        let profileHigh = createProfile(
            curve: .rapidActing,
            useCustomPeakTime: true,
            insulinPeakTime: 150
        )
        let resultHigh = try IobCalculation.iobCalc(
            treatment: treatment,
            time: now,
            dia: 3,
            profile: profileHigh
        )
        #expect(resultHigh != nil)

        // Test lower limit (50)
        let profileLow = createProfile(
            curve: .rapidActing,
            useCustomPeakTime: true,
            insulinPeakTime: 30
        )
        let resultLow = try IobCalculation.iobCalc(
            treatment: treatment,
            time: now,
            dia: 3,
            profile: profileLow
        )
        #expect(resultLow != nil)
    }

    @Test("should calculate IOB with ultra-rapid insulin") func calculateUltraRapid() async throws {
        let now = Date()
        let thirtyMinsAgo = now - 30.minutesToSeconds
        let treatment = createTreatment(insulin: 2, timestamp: thirtyMinsAgo)

        let profile = createProfile(curve: .ultraRapid)

        let result = try IobCalculation.iobCalc(
            treatment: treatment,
            time: now,
            dia: 3,
            profile: profile
        )

        #expect(result != nil)
        #expect(result!.activityContrib.isWithin(0.0001, of: 0.01569))
        #expect(result!.iobContrib.isWithin(0.0001, of: 1.7202))
    }

    @Test("should handle peak time limits for ultra-rapid insulin") func handlePeakTimeLimitsUltraRapid() async throws {
        let now = Date()
        let thirtyMinsAgo = now - 30.minutesToSeconds
        let treatment = createTreatment(insulin: 2, timestamp: thirtyMinsAgo)

        // Test upper limit (100)
        let profileHigh = createProfile(
            curve: .ultraRapid,
            useCustomPeakTime: true,
            insulinPeakTime: 120
        )
        let resultHigh = try IobCalculation.iobCalc(
            treatment: treatment,
            time: now,
            dia: 3,
            profile: profileHigh
        )
        #expect(resultHigh != nil)

        // Test lower limit (35)
        let profileLow = createProfile(
            curve: .ultraRapid,
            useCustomPeakTime: true,
            insulinPeakTime: 30
        )
        let resultLow = try IobCalculation.iobCalc(
            treatment: treatment,
            time: now,
            dia: 3,
            profile: profileLow
        )
        #expect(resultLow != nil)
    }

    @Test("should handle insulin activity after DIA") func handleActivityAfterDIA() async throws {
        let now = Date()
        let fourHoursAgo = now - (4 * 60 * 60)
        let treatment = createTreatment(insulin: 2, timestamp: fourHoursAgo)

        let result = try IobCalculation.iobCalc(
            treatment: treatment,
            time: now,
            dia: 3,
            profile: createProfile()
        )

        #expect(result != nil)
        #expect(result?.activityContrib == 0)
        #expect(result?.iobContrib == 0)
    }
}
