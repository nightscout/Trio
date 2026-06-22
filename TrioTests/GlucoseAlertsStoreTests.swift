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

    // MARK: - availableActiveOptions for new alarms

    private static func storeWithOnly(_ alerts: [GlucoseAlert]) -> GlucoseAlertsStore {
        let store = Self.makeStore()
        store.alerts = alerts
        return store
    }

    @Test("Single .always covers everything: no options available") func alwaysCoversAll() {
        let existing = GlucoseAlert(type: .low) // default .always
        let store = Self.storeWithOnly([existing])
        #expect(store.availableActiveOptions(forNewAlarmOfType: .low).isEmpty)
    }

    @Test("Only .day taken → only .night available") func dayTakenOffersNight() {
        var existing = GlucoseAlert(type: .low)
        existing.activeOption = .day
        let store = Self.storeWithOnly([existing])
        #expect(store.availableActiveOptions(forNewAlarmOfType: .low) == [.night])
    }

    @Test("Only .night taken → only .day available") func nightTakenOffersDay() {
        var existing = GlucoseAlert(type: .high)
        existing.activeOption = .night
        let store = Self.storeWithOnly([existing])
        #expect(store.availableActiveOptions(forNewAlarmOfType: .high) == [.day])
    }

    @Test(".day + .night both taken → none available") func dayAndNightTakenLocked() {
        var day = GlucoseAlert(type: .forecastedLow)
        day.activeOption = .day
        var night = GlucoseAlert(type: .forecastedLow)
        night.activeOption = .night
        let store = Self.storeWithOnly([day, night])
        #expect(store.availableActiveOptions(forNewAlarmOfType: .forecastedLow).isEmpty)
    }

    @Test("No alarm of this type → all three options available") func emptyOffersAll() {
        let store = Self.storeWithOnly([])
        #expect(store.availableActiveOptions(forNewAlarmOfType: .carbsRequired) == [.always, .day, .night])
    }

    @Test("Gating is per-type — other types don't block") func gatingIsPerType() {
        let lowAlways = GlucoseAlert(type: .low) // .always blocks Low
        let store = Self.storeWithOnly([lowAlways])
        #expect(store.availableActiveOptions(forNewAlarmOfType: .low).isEmpty)
        #expect(store.availableActiveOptions(forNewAlarmOfType: .high) == [.always, .day, .night])
    }

    @Test("Editing an existing .day alarm: .always becomes pickable again") func editingExcludesSelf() {
        var existing = GlucoseAlert(type: .urgentLow)
        existing.activeOption = .day
        let store = Self.storeWithOnly([existing])
        let available = store.availableActiveOptions(forType: .urgentLow, excludingAlertID: existing.id)
        #expect(available == [.always, .day, .night])
    }

    @Test("Editing one of two split alarms: only own window available") func editingOneOfTwoSplit() {
        var day = GlucoseAlert(type: .low)
        day.activeOption = .day
        var night = GlucoseAlert(type: .low)
        night.activeOption = .night
        let store = Self.storeWithOnly([day, night])
        // Editing the .day alarm: .night is taken by the other, .always would conflict with .night.
        let editingDay = store.availableActiveOptions(forType: .low, excludingAlertID: day.id)
        #expect(editingDay == [.day])
    }
}
