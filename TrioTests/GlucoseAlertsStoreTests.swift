import Foundation
import Testing

@testable import Trio

@Suite("Trio Alerts: GlucoseAlertsStore seed + backfill", .serialized) struct GlucoseAlertsStoreTests {
    private static func makeStore(seed: [GlucoseAlert]? = nil) -> GlucoseAlertsStore {
        let suiteName = "GlucoseAlertsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let alertsKey = "alerts.\(suiteName)"
        let configKey = "config.\(suiteName)"
        if let seed {
            let data = try? JSONEncoder().encode(seed)
            defaults.set(data, forKey: alertsKey)
        }
        return GlucoseAlertsStore(defaults: defaults, alertsKey: alertsKey, configKey: configKey)
    }

    @Test("Fresh store seeds one alert per type") func freshSeedAllTypes() {
        let store = Self.makeStore()
        let types = Set(store.alerts.map(\.type))
        for type in GlucoseAlertType.allCases {
            #expect(types.contains(type), "Missing seed for \(type)")
        }
        #expect(store.alerts.count == GlucoseAlertType.allCases.count)
    }

    @Test("Legacy load (no carbsRequired) backfills the new type") func legacyLoadBackfillsCarbsRequired() {
        let legacy: [GlucoseAlert] = [
            GlucoseAlert(type: .urgentLow),
            GlucoseAlert(type: .low),
            GlucoseAlert(type: .forecastedLow),
            GlucoseAlert(type: .high)
        ]
        let store = Self.makeStore(seed: legacy)
        let types = Set(store.alerts.map(\.type))
        #expect(types.contains(.carbsRequired))
        #expect(store.alerts.count == GlucoseAlertType.allCases.count)
    }

    @Test("Backfill preserves user customizations on existing entries") func backfillPreservesCustomizations() {
        var custom = GlucoseAlert(type: .low)
        custom.thresholdMgDL = 65
        custom.soundFilename = "custom_sound.caf"
        custom.isEnabled = false
        let store = Self.makeStore(seed: [custom])
        let restored = store.alerts.first { $0.type == .low }!
        #expect(restored.thresholdMgDL == 65)
        #expect(restored.soundFilename == "custom_sound.caf")
        #expect(restored.isEnabled == false)
        // And new types still got appended.
        #expect(store.alerts.contains { $0.type == .carbsRequired })
    }

    @Test("Full load doesn't double up on existing types") func fullLoadNoDuplicates() {
        let full = GlucoseAlertType.allCases.map { GlucoseAlert(type: $0) }
        let store = Self.makeStore(seed: full)
        let countsByType = Dictionary(grouping: store.alerts, by: \.type).mapValues(\.count)
        for type in GlucoseAlertType.allCases {
            #expect(countsByType[type] == 1, "Duplicated \(type) on load")
        }
    }
}
