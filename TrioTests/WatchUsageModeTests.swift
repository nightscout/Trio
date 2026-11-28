import Foundation
import Testing
@testable import Trio

@Suite("Watch Usage Mode") struct WatchUsageModeTests {
    private func decode(_ json: String) throws -> TrioSettings {
        try JSONDecoder().decode(TrioSettings.self, from: Data(json.utf8))
    }

    @Test("Companion allows treatments and adjustments") func companionPermissions() {
        #expect(WatchUsageMode.companion.allowsTreatments)
        #expect(WatchUsageMode.companion.allowsAdjustments)
    }

    @Test("Adjustments allows only overrides and temp targets") func adjustmentsPermissions() {
        #expect(!WatchUsageMode.adjustments.allowsTreatments)
        #expect(WatchUsageMode.adjustments.allowsAdjustments)
    }

    @Test("View allows no actions") func viewPermissions() {
        #expect(!WatchUsageMode.view.allowsTreatments)
        #expect(!WatchUsageMode.view.allowsAdjustments)
    }

    @Test("Missing or unknown value falls back to companion") func fallbackToCompanion() throws {
        #expect(try decode("{}").watchUsageMode == .companion)
        #expect(try decode(#"{"watchUsageMode": "unknown"}"#).watchUsageMode == .companion)
    }

    @Test("Every mode round-trips") func everyModeRoundTrips() throws {
        for mode in WatchUsageMode.allCases {
            var settings = TrioSettings()
            settings.watchUsageMode = mode
            let decoded = try JSONDecoder().decode(TrioSettings.self, from: JSONEncoder().encode(settings))
            #expect(decoded.watchUsageMode == mode)
        }
    }

    @Test("Bundled defaults use companion") func bundledDefaultIsCompanion() throws {
        let defaults = OpenAPS.defaults(for: OpenAPS.Trio.settings)
        let settings = try #require(TrioSettings(from: defaults))
        #expect(settings.watchUsageMode == .companion)
    }
}
