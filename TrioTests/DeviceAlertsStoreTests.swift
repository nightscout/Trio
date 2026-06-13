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
        if let seed {
            let data = try? JSONEncoder().encode(seed)
            defaults.set(data, forKey: "trio.deviceAlertSeverityConfigs.v1")
        }
        return DeviceAlertsStore(defaults: defaults, configsKey: "trio.deviceAlertSeverityConfigs.v1")
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
}
