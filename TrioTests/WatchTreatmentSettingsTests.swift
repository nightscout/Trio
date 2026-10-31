import Foundation
import Testing
@testable import Trio

@Suite("Watch Treatment Settings") struct WatchTreatmentSettingsTests {
    private func decode(_ json: String) throws -> TrioSettings {
        try JSONDecoder().decode(TrioSettings.self, from: Data(json.utf8))
    }

    @Test("Missing key keeps watch treatments allowed") func missingKeyDefaultsToAllowed() throws {
        #expect(try decode("{}").allowWatchTreatments)
    }

    @Test("Stored false value is decoded") func storedFalseIsDecoded() throws {
        #expect(try decode(#"{"allowWatchTreatments": false}"#).allowWatchTreatments == false)
    }

    @Test("Value round-trips through encoding") func roundTrip() throws {
        var settings = TrioSettings()
        settings.allowWatchTreatments = false
        let decoded = try JSONDecoder().decode(TrioSettings.self, from: JSONEncoder().encode(settings))
        #expect(!decoded.allowWatchTreatments)
    }

    @Test("Bundled defaults allow watch treatments") func bundledDefaultsAllow() throws {
        let defaults = OpenAPS.defaults(for: OpenAPS.Trio.settings)
        let settings = try #require(TrioSettings(from: defaults))
        #expect(settings.allowWatchTreatments)
    }
}
