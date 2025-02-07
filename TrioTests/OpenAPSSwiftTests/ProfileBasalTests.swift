import Foundation
import Testing
@testable import Trio

@Suite("Basal Tests") struct BasalTests {
    @Test("should find current basal rate in a sample profile") func findCurrentBasalRate() async throws {
        let now = Calendar.current.date(from: DateComponents(year: 2025, month: 1, day: 1, hour: 2))!
        let basalProfile = [
            BasalProfileEntry(start: "00:00", minutes: 0, rate: 1.0),
            BasalProfileEntry(start: "02:00", minutes: 120, rate: 2.0),
            BasalProfileEntry(start: "03:00", minutes: 180, rate: 3.0)
        ]

        let rate = try Basal.basalLookup(basalProfile, now: now)
        #expect(rate == 2.0)
    }

    @Test("should find current basal rate for midnight in a sample profile") func findMidnightBasalRate() async throws {
        let now = Calendar.current.date(from: DateComponents(year: 2025, month: 1, day: 1, hour: 0))!
        let basalProfile = [
            BasalProfileEntry(start: "00:00", minutes: 0, rate: 1.0),
            BasalProfileEntry(start: "02:00", minutes: 120, rate: 2.0),
            BasalProfileEntry(start: "03:00", minutes: 180, rate: 3.0)
        ]

        let rate = try Basal.basalLookup(basalProfile, now: now)
        #expect(rate == 1.0)
    }

    @Test("should find current basal rate for 3am in a sample profile") func findThreeAmBasalRate() async throws {
        let now = Calendar.current.date(from: DateComponents(year: 2025, month: 1, day: 1, hour: 3))!
        let basalProfile = [
            BasalProfileEntry(start: "00:00", minutes: 0, rate: 1.0),
            BasalProfileEntry(start: "02:00", minutes: 120, rate: 2.0),
            BasalProfileEntry(start: "03:00", minutes: 180, rate: 3.0)
        ]

        let rate = try Basal.basalLookup(basalProfile, now: now)
        #expect(rate == 3.0)
    }

    @Test("should return nil with an empty profile") func handleEmptyProfile() async throws {
        let rate = try Basal.basalLookup([])
        #expect(rate == nil)
    }

    @Test("should handle a profile with just one rate") func handleSingleRateProfile() async throws {
        let basalProfile = [
            BasalProfileEntry(start: "00:00", minutes: 0, rate: 1.0)
        ]

        let rate = try Basal.basalLookup(basalProfile)
        #expect(rate == 1.0)
    }

    @Test("should return nil with a zero rate") func handleZeroRate() async throws {
        let basalProfile = [
            BasalProfileEntry(start: "00:00", minutes: 0, rate: 0.0)
        ]

        let rate = try Basal.basalLookup(basalProfile)
        #expect(rate == nil)
    }

    @Test("should properly compute maxDailyBasal") func computeMaxDailyBasal() async throws {
        let basalProfile = [
            BasalProfileEntry(start: "00:00", minutes: 0, rate: 1.0),
            BasalProfileEntry(start: "02:00", minutes: 120, rate: 2.0),
            BasalProfileEntry(start: "03:00", minutes: 180, rate: 3.0)
        ]

        let maxRate = Basal.maxDailyBasal(basalProfile)
        #expect(maxRate == 3.0)
    }

    @Test("should return nil for maxDailyBasal with empty profile") func handleEmptyProfileForMaxDaily() async throws {
        let maxRate = Basal.maxDailyBasal([])
        #expect(maxRate == nil)
    }
}
