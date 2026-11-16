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

    // Requests the iPhone handles from the Watch (see BaseWatchManager.session(_:didReceiveMessage:))
    private let bolus: [String: Any] = [WatchMessageKeys.bolus: 1.5]
    private let carbs: [String: Any] = [WatchMessageKeys.carbs: 20, WatchMessageKeys.date: 1_800_000_000.0]
    private let meal: [String: Any] = [
        WatchMessageKeys.bolus: 1.5,
        WatchMessageKeys.carbs: 20,
        WatchMessageKeys.date: 1_800_000_000.0
    ]
    private let adjustments: [[String: Any]] = [
        [WatchMessageKeys.activateOverride: "Exercise"],
        [WatchMessageKeys.cancelOverride: true],
        [WatchMessageKeys.activateTempTarget: "Pre-Meal"],
        [WatchMessageKeys.cancelTempTarget: true]
    ]
    private let alwaysAllowed: [[String: Any]] = [
        [WatchMessageKeys.requestWatchUpdate: WatchMessageKeys.watchState],
        [WatchMessageKeys.requestBolusRecommendation: true, WatchMessageKeys.carbs: 20],
        [WatchMessageKeys.snoozeDuration: 30]
    ]

    @Test("Treatment requests are only allowed in companion mode") func treatmentRequests() {
        for message in [bolus, carbs, meal] {
            #expect(WatchUsageMode.companion.allows(watchMessage: message))
            #expect(!WatchUsageMode.adjustments.allows(watchMessage: message))
            #expect(!WatchUsageMode.view.allows(watchMessage: message))
        }
    }

    @Test("Override and temp target requests are rejected in view mode") func adjustmentRequests() {
        for message in adjustments {
            #expect(WatchUsageMode.companion.allows(watchMessage: message))
            #expect(WatchUsageMode.adjustments.allows(watchMessage: message))
            #expect(!WatchUsageMode.view.allows(watchMessage: message))
        }
    }

    @Test("Data requests and alert snoozes are allowed in every mode") func dataRequests() {
        for message in alwaysAllowed {
            for mode in WatchUsageMode.allCases {
                #expect(mode.allows(watchMessage: message))
            }
        }
    }

    @Test("Carbs with a date are a treatment even when a recommendation is requested") func recommendationWithDate() {
        var message = carbs
        message[WatchMessageKeys.requestBolusRecommendation] = true
        #expect(!WatchUsageMode.adjustments.allows(watchMessage: message))
        #expect(!WatchUsageMode.view.allows(watchMessage: message))
    }

    @Test("Values the iPhone does not act on are not treated as requests") func ignoredValues() {
        let ignored: [[String: Any]] = [
            [WatchMessageKeys.cancelOverride: false],
            [WatchMessageKeys.cancelTempTarget: false],
            [WatchMessageKeys.carbs: 20]
        ]
        for message in ignored {
            #expect(WatchUsageMode.view.allows(watchMessage: message))
        }
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
