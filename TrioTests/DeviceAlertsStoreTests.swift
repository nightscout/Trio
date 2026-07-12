import Foundation
import Testing

@testable import Trio

@Suite("Trio Alerts: DeviceAlertsStore variant precedence", .serialized) struct DeviceAlertsStoreTests {
    /// Each test gets a unique suite name so UserDefaults state can't leak
    /// between tests in parallel runs.
    private static func makeStore(seed: [DeviceAlertSeverityConfig]? = nil) -> DeviceAlertsStore {
        let suiteName = "DeviceAlertsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let configsKey = "configs.\(suiteName)"
        let snoozesKey = "snoozes.\(suiteName)"
        if let seed {
            let data = try? JSONEncoder().encode(seed)
            defaults.set(data, forKey: configsKey)
        }
        return DeviceAlertsStore(defaults: defaults, configsKey: configsKey, snoozesKey: snoozesKey)
    }

    @Test("Fresh store seeds one .always config per severity") func freshSeed() {
        let store = Self.makeStore()
        for severity in DeviceAlertSeverity.allCases {
            let always = store.configs.first { $0.severity == severity && $0.activeOption == .always }
            #expect(always != nil, "Missing .always seed for \(severity)")
        }
        #expect(store.configs.count == DeviceAlertSeverity.allCases.count)
    }

    @Test("config(for:isNight:) returns .day variant during daytime") func dayMatchPicksDayVariant() {
        var dayOnly = DeviceAlertSeverityConfig(severity: .critical, activeOption: .day)
        dayOnly.soundFilename = "day.caf"
        let store = Self.makeStore(seed: [
            DeviceAlertSeverityConfig(severity: .critical, activeOption: .always),
            dayOnly,
            DeviceAlertSeverityConfig(severity: .timeSensitive, activeOption: .always),
            DeviceAlertSeverityConfig(severity: .normal, activeOption: .always)
        ])
        let match = store.config(for: .critical, at: Date(), isNight: false)
        #expect(match?.soundFilename == "day.caf")
    }

    @Test("config(for:isNight:) returns .night variant overnight") func nightMatchPicksNightVariant() {
        var nightOnly = DeviceAlertSeverityConfig(severity: .critical, activeOption: .night)
        nightOnly.soundFilename = "night.caf"
        let store = Self.makeStore(seed: [
            DeviceAlertSeverityConfig(severity: .critical, activeOption: .always),
            nightOnly,
            DeviceAlertSeverityConfig(severity: .timeSensitive, activeOption: .always),
            DeviceAlertSeverityConfig(severity: .normal, activeOption: .always)
        ])
        let match = store.config(for: .critical, at: Date(), isNight: true)
        #expect(match?.soundFilename == "night.caf")
    }

    @Test("Day variant doesn't match at night — falls back to .always") func dayVariantSkippedAtNight() {
        var always = DeviceAlertSeverityConfig(severity: .critical, activeOption: .always)
        always.soundFilename = "fallback.caf"
        var dayOnly = DeviceAlertSeverityConfig(severity: .critical, activeOption: .day)
        dayOnly.soundFilename = "day.caf"
        let store = Self.makeStore(seed: [
            always,
            dayOnly,
            DeviceAlertSeverityConfig(severity: .timeSensitive, activeOption: .always),
            DeviceAlertSeverityConfig(severity: .normal, activeOption: .always)
        ])
        let match = store.config(for: .critical, at: Date(), isNight: true)
        #expect(match?.soundFilename == "fallback.caf")
    }

    @Test("Disabled variants are skipped; falls back to next enabled") func disabledVariantSkipped() {
        // Use timeSensitive — Critical configs are always considered enabled
        // regardless of the stored isEnabled flag.
        var dayDisabled = DeviceAlertSeverityConfig(severity: .timeSensitive, activeOption: .day)
        dayDisabled.isEnabled = false
        dayDisabled.soundFilename = "disabled-day.caf"
        var alwaysFallback = DeviceAlertSeverityConfig(severity: .timeSensitive, activeOption: .always)
        alwaysFallback.soundFilename = "always.caf"
        let store = Self.makeStore(seed: [
            DeviceAlertSeverityConfig(severity: .critical, activeOption: .always),
            alwaysFallback,
            dayDisabled,
            DeviceAlertSeverityConfig(severity: .normal, activeOption: .always)
        ])
        let match = store.config(for: .timeSensitive, at: Date(), isNight: false)
        #expect(match?.soundFilename == "always.caf")
    }

    @Test("Critical tier ignores stored isEnabled flag") func criticalAlwaysEnabled() {
        var disabledCritical = DeviceAlertSeverityConfig(severity: .critical, activeOption: .always)
        disabledCritical.isEnabled = false
        disabledCritical.soundFilename = "critical.caf"
        let store = Self.makeStore(seed: [
            disabledCritical,
            DeviceAlertSeverityConfig(severity: .timeSensitive, activeOption: .always),
            DeviceAlertSeverityConfig(severity: .normal, activeOption: .always)
        ])
        let match = store.config(for: .critical, at: Date(), isNight: false)
        #expect(match?.soundFilename == "critical.caf")
    }

    @Test("All variants disabled returns nil") func allDisabledReturnsNil() {
        var always = DeviceAlertSeverityConfig(severity: .normal, activeOption: .always)
        always.isEnabled = false
        let store = Self.makeStore(seed: [
            DeviceAlertSeverityConfig(severity: .critical, activeOption: .always),
            DeviceAlertSeverityConfig(severity: .timeSensitive, activeOption: .always),
            always
        ])
        #expect(store.config(for: .normal, at: Date(), isNight: false) == nil)
    }

    @Test("canDelete protects the last .always per severity") func canDeleteLastAlways() {
        let store = Self.makeStore()
        let onlyAlways = store.configs.first { $0.severity == .critical && $0.activeOption == .always }!
        #expect(!store.canDelete(onlyAlways))
    }

    @Test("canDelete allows removing one of two .always in the same tier") func canDeleteSecondAlways() {
        let extraAlways = DeviceAlertSeverityConfig(severity: .critical, activeOption: .always)
        let store = Self.makeStore(seed: [
            DeviceAlertSeverityConfig(severity: .critical, activeOption: .always),
            extraAlways,
            DeviceAlertSeverityConfig(severity: .timeSensitive, activeOption: .always),
            DeviceAlertSeverityConfig(severity: .normal, activeOption: .always)
        ])
        #expect(store.canDelete(extraAlways))
    }

    @Test("canDelete always allows non-always variants") func canDeleteDayOrNight() {
        let dayOnly = DeviceAlertSeverityConfig(severity: .critical, activeOption: .day)
        let store = Self.makeStore(seed: [
            DeviceAlertSeverityConfig(severity: .critical, activeOption: .always),
            dayOnly,
            DeviceAlertSeverityConfig(severity: .timeSensitive, activeOption: .always),
            DeviceAlertSeverityConfig(severity: .normal, activeOption: .always)
        ])
        #expect(store.canDelete(dayOnly))
    }

    // MARK: - Per-tier snooze

    /// Builds a unique UserDefaults suite (UUID), wipes its persistent domain,
    /// and returns the defaults plus the derived keys — so a test can seed or
    /// reload across multiple stores on the same backing store.
    private static func makeSuite() -> (defaults: UserDefaults, configsKey: String, snoozesKey: String) {
        let suiteName = "DeviceAlertsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let configsKey = "configs.\(suiteName)"
        let snoozesKey = "snoozes.\(suiteName)"
        return (defaults, configsKey, snoozesKey)
    }

    @Test("Snoozed tier is active before its expiry") func snoozeTimeSensitiveActiveBeforeExpiry() {
        let now = Date()
        let store = Self.makeStore()
        store.snoozeTier(.timeSensitive, until: now.addingTimeInterval(600))
        #expect(store.isTierSnoozed(.timeSensitive, at: now))
        #expect(!store.isTierSnoozed(.timeSensitive, at: now.addingTimeInterval(601)))
    }

    @Test("Snoozing one tier doesn't affect another") func snoozeDoesNotAffectOtherTiers() {
        let now = Date()
        let store = Self.makeStore()
        store.snoozeTier(.timeSensitive, until: now.addingTimeInterval(600))
        #expect(!store.isTierSnoozed(.normal, at: now))
    }

    @Test("Snooze with a past until removes the key") func snoozeWithPastUntilRemoves() {
        let now = Date()
        let store = Self.makeStore()
        store.snoozeTier(.timeSensitive, until: now.addingTimeInterval(-1))
        #expect(!store.isTierSnoozed(.timeSensitive, at: now))
        #expect(store.tierSnoozes["timeSensitive"] == nil)

        // Live snooze, then a past until should remove the existing key.
        store.snoozeTier(.timeSensitive, until: now.addingTimeInterval(600))
        #expect(store.tierSnoozes["timeSensitive"] != nil)
        store.snoozeTier(.timeSensitive, until: now.addingTimeInterval(-1))
        #expect(store.tierSnoozes["timeSensitive"] == nil)
    }

    @Test("Snooze persists across a store reload") func snoozePersistsAcrossStoreReload() {
        let now = Date()
        let suite = Self.makeSuite()
        let store1 = DeviceAlertsStore(
            defaults: suite.defaults,
            configsKey: suite.configsKey,
            snoozesKey: suite.snoozesKey
        )
        store1.snoozeTier(.timeSensitive, until: now.addingTimeInterval(3600))
        let store2 = DeviceAlertsStore(
            defaults: suite.defaults,
            configsKey: suite.configsKey,
            snoozesKey: suite.snoozesKey
        )
        #expect(store2.isTierSnoozed(.timeSensitive, at: now))
    }

    @Test("Expired snooze is pruned on load") func expiredSnoozeIsPrunedOnLoad() {
        let now = Date()
        let suite = Self.makeSuite()
        let expired: [String: Date] = ["timeSensitive": now.addingTimeInterval(-60)]
        suite.defaults.set(try? JSONEncoder().encode(expired), forKey: suite.snoozesKey)
        let store = DeviceAlertsStore(
            defaults: suite.defaults,
            configsKey: suite.configsKey,
            snoozesKey: suite.snoozesKey
        )
        #expect(store.tierSnoozes.isEmpty)
        #expect(!store.isTierSnoozed(.timeSensitive, at: now))

        // Companion: seed both an expired and a future entry — only the future
        // .normal entry should survive the load-time prune.
        let suite2 = Self.makeSuite()
        let mixed: [String: Date] = [
            "timeSensitive": now.addingTimeInterval(-60),
            "normal": now.addingTimeInterval(3600)
        ]
        suite2.defaults.set(try? JSONEncoder().encode(mixed), forKey: suite2.snoozesKey)
        let store2 = DeviceAlertsStore(
            defaults: suite2.defaults,
            configsKey: suite2.configsKey,
            snoozesKey: suite2.snoozesKey
        )
        #expect(store2.tierSnoozes["timeSensitive"] == nil)
        #expect(store2.tierSnoozes["normal"] != nil)
        #expect(store2.isTierSnoozed(.normal, at: now))
    }

    @Test("isTierSnoozed is false exactly at the until instant") func isTierSnoozedFalseExactlyAtUntilInstant() {
        let now = Date()
        let until = now.addingTimeInterval(600)
        let store = Self.makeStore()
        store.snoozeTier(.timeSensitive, until: until)
        #expect(!store.isTierSnoozed(.timeSensitive, at: until))
        #expect(store.isTierSnoozed(.timeSensitive, at: until.addingTimeInterval(-0.001)))
    }

    @Test("Store accepts a critical snooze") func storeAcceptsCriticalSnooze() {
        let now = Date()
        let store = Self.makeStore()
        store.snoozeTier(.critical, until: now.addingTimeInterval(600))
        #expect(store.isTierSnoozed(.critical, at: now))
    }
}
