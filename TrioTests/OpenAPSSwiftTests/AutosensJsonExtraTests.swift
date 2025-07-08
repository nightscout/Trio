import Foundation
import Testing
@testable import Trio

@Suite("Autosens using real JSON from bundle", .serialized) struct AutosensJsonExtraTests {
    let timeZoneForTests = TimeZoneForTests()

    // static func from<T: Decodable>(string: String) throws -> T
    func loadJson<T: Decodable>(_ name: String) throws -> T {
        let testBundle = Bundle(for: BundleReference.self)
        let path = testBundle.path(forResource: name, ofType: "json")!
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        return try JSONCoding.decoder.decode(T.self, from: data)
    }

    @Test("Test with resistance") func generateJavascriptInputs() throws {
        let glucose: [BloodGlucose] = try loadJson("as-glucose")
        let pump: [PumpHistoryEvent] = try loadJson("as-pump")
        let basalProfile: [BasalProfileEntry] = try loadJson("as-basal")
        let profile: Profile = try loadJson("as-profile")
        let carbs: [CarbsEntry] = try loadJson("as-carbs")
        let tempTargets: [TempTarget] = try loadJson("as-temp-targets")

        let clock = Date("2025-06-08T00:14:35.481Z")!

        timeZoneForTests.setTimezone(identifier: "America/Los_Angeles")

        let autosensResult = try AutosensGenerator.generate(
            glucose: glucose,
            pumpHistory: pump,
            basalProfile: basalProfile,
            profile: profile,
            carbs: carbs,
            tempTargets: tempTargets,
            maxDeviations: 96,
            clock: clock,
            includeDeviationsForTesting: true
        )

        let deviationsUnsorted: [Decimal] = try loadJson("deviationsUnsorted")

        #expect(autosensResult.ratio == 1.2)
        #expect(autosensResult.newisf == 46)
        #expect(deviationsUnsorted.count == autosensResult.deviationsUnsorted?.count)

        for (ref, calc) in zip(deviationsUnsorted, autosensResult.deviationsUnsorted!) {
            // we can get differences due to rounding inconsistencies between
            // javascript and swift with negative numbers
            #expect(ref.isWithin(0.01, of: calc))
        }

        timeZoneForTests.resetTimezone()
    }
}
