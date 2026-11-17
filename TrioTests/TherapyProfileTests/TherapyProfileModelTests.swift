import Foundation
import Testing
@testable import Trio

@Suite("Therapy Profile Model Tests") struct TherapyProfileModelTests {
    @Test("Fingerprint matches the shared test vector") func fingerprintVector() {
        let canonical = TrioTherapyProfile.fingerprintCanonicalString(
            basal: [(0, 0.85), (21600, 1)],
            carbratio: [(0, 10)],
            sens: [(0, 50)],
            targetLow: [(0, 100)],
            targetHigh: [(0, 110)]
        )
        #expect(
            canonical ==
                "basal=0:0.850,21600:1.000;carbratio=0:10.000;sens=0:50.000;target_low=0:100.000;target_high=0:110.000"
        )
        #expect(TrioTherapyProfile.fingerprint(of: canonical) == "3e603478d512da04")

        let profile = TherapyProfileFixtures.profile("Any")
        #expect(profile.matchesFingerprint(profile.fingerprint(units: .mgdL).uppercased()))
        #expect(profile.matchesFingerprint(profile.fingerprint(units: .mmolL)))
        #expect(!profile.matchesFingerprint("0000000000000000"))
    }

    @Test("mmol/L fingerprint uses the converted glucose values") func fingerprintMmolL() {
        #expect(
            TherapyProfileFixtures.profile("Any").fingerprintCanonicalString(units: .mmolL) ==
                "basal=0:0.850,21600:1.000;carbratio=0:10.000;sens=0:2.800;target_low=0:5.600;target_high=0:5.600"
        )
    }

    @Test("A target's high value is its low value") func singleTarget() {
        let profile = TherapyProfileFixtures.profile("Range", target: [(0, 100, 110), (43200, 95, 120)])
        #expect(profile.target.map(\.high) == [100, 95])
        #expect(profile.bgTargets.targets.map(\.high) == [100, 95])
        #expect(
            profile.fingerprintCanonicalString(units: .mgdL).hasSuffix(
                "target_low=0:100.000,43200:95.000;target_high=0:100.000,43200:95.000"
            )
        )
    }

    @Test("Basal rates are kept at three decimal places") func basalRatesRounded() throws {
        let danaRates = (0 ... 300).map { Double($0) / 100 }.filter { $0 > 0 }.map { Decimal($0) }
        let noisy = danaRates.filter { $0 != $0.rounded(scale: 3) }
        #expect(!noisy.isEmpty)

        let fromEditor = TrioTherapyProfile(
            name: "Dana",
            basalProfile: noisy.enumerated().prefix(48).map { index, rate in
                BasalProfileEntry(start: TrioTherapyProfile.startString(seconds: index * 1800), minutes: index * 30, rate: rate)
            },
            carbRatios: CarbRatios(units: .grams, schedule: []),
            insulinSensitivities: InsulinSensitivities(units: .mgdL, userPreferredUnits: .mgdL, sensitivities: []),
            bgTargets: BGTargets(units: .mgdL, userPreferredUnits: .mgdL, targets: [])
        )
        let exact = noisy.prefix(48).compactMap { Decimal(string: String(format: "%.2f", Double($0))) }
        #expect(fromEditor.basal.map(\.value) == exact)

        let sevenHundredths = try #require(Decimal(string: "0.07"))
        let remote = TrioTherapyProfile(
            name: "Dana",
            basal: [TherapyScheduleEntry(seconds: 0, value: sevenHundredths)],
            carbRatio: [],
            sensitivity: [],
            target: []
        )
        let live = TrioTherapyProfile(
            name: "Dana",
            basal: [TherapyScheduleEntry(seconds: 0, value: Decimal(0.07))],
            carbRatio: [],
            sensitivity: [],
            target: []
        )
        #expect(Decimal(0.07) != sevenHundredths)
        #expect(live.hasSameValues(as: remote))
        #expect(live == remote)
    }

    @Test("Profile converts to the settings files and back") func settingsFilesRoundTrip() {
        let profile = TherapyProfileFixtures.profile(
            "Round",
            basal: [(0, 0.5), (5400, 0.75), (84600, 1.2)],
            carbratio: [(0, 8.5), (43200, 12)],
            sens: [(0, 45), (1800, 60)],
            target: [(0, 95, 95), (79200, 110, 110)]
        )
        #expect(profile.basalProfileEntries[1].start == "01:30:00")
        #expect(profile.basalProfileEntries[1].minutes == 90)
        #expect(profile.carbRatios.schedule[1].offset == 720)
        #expect(profile.bgTargets.targets[1].start == "22:00:00")
        let back = TrioTherapyProfile(
            name: "Round",
            basalProfile: profile.basalProfileEntries,
            carbRatios: profile.carbRatios,
            insulinSensitivities: profile.insulinSensitivities,
            bgTargets: profile.bgTargets
        )
        #expect(back == profile)
    }

    @Test("Start times are whole seconds from midnight, without a time zone") func startTimesIgnoreTimeZone() throws {
        let profile = TherapyProfileFixtures.profile("Travel", basal: [(0, 0.5), (5400, 0.6), (7200, 0.7), (9000, 0.8)])
        #expect(profile.basalProfileEntries.map(\.start) == ["00:00:00", "01:30:00", "02:00:00", "02:30:00"])
        #expect(profile.basalProfileEntries.map(\.minutes) == [0, 90, 120, 150])
        #expect(profile.bgTargets.targets.map(\.offset) == [0])
        #expect(TherapyProfileValidator.timeString(5400).contains("1:30"))
        #expect(TherapyProfileValidator.timeString(9000).contains("2:30"))
    }
}
