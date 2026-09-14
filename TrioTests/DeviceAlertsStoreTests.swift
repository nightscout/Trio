import Foundation
import LoopKit
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

/// Regression cover for issue #1371: device alarms fired without the tone the
/// user picked, so no alarm sound played and the entitlement-less
/// `CriticalAlertAudioPlayer` fallback (which needs a filename) never engaged.
/// Pump plugins issue alerts with `sound: nil`, so the tier config is the only
/// thing that can supply a sound.
@Suite("Trio Alerts: device alarm tier config application", .serialized) struct DeviceAlarmTierConfigTests {
    private static func makeStore(seed: [DeviceAlertSeverityConfig]? = nil) -> DeviceAlertsStore {
        let suiteName = "DeviceAlarmTierConfigTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let configsKey = "configs.\(suiteName)"
        let snoozesKey = "snoozes.\(suiteName)"
        if let seed {
            defaults.set(try? JSONEncoder().encode(seed), forKey: configsKey)
        }
        return DeviceAlertsStore(defaults: defaults, configsKey: configsKey, snoozesKey: snoozesKey)
    }

    /// Mirrors what MedtrumKit emits: no sound, no interruption level.
    private static func pluginAlert(_ identifier: Alert.Identifier) -> Alert {
        let content = Alert.Content(title: "t", body: "b", acknowledgeActionButtonLabel: "OK")
        return Alert(
            identifier: identifier,
            foregroundContent: content,
            backgroundContent: content,
            trigger: .immediate
        )
    }

    private static let patchEmpty = Alert.Identifier(
        managerIdentifier: "Medtrum",
        alertIdentifier: "com.nightscout.medtrumkit.patch-empty"
    )
    private static let reservoirLow = Alert.Identifier(
        managerIdentifier: "Medtrum",
        alertIdentifier: "com.nightscout.medtrumkit.reservoir-low"
    )

    // MARK: - Tone

    @Test("Critical device alarm carries the user's selected tone") func criticalGetsSelectedTone() throws {
        let entry = try #require(AlertCatalogRegistry.lookup(Self.patchEmpty))
        var config = DeviceAlertSeverityConfig(severity: .critical)
        config.soundFilename = "synth.caf"
        config.playsSound = true

        let issued = Self.pluginAlert(Self.patchEmpty)
        #expect(issued.sound == nil, "Precondition: plugins emit no sound")

        let effective = BaseTrioAlertManager.applyDeviceSeverityConfig(config, entry: entry, to: issued)
        #expect(effective.sound == .sound(name: "synth.caf"))
        // The critical-audio fallback keys off this filename.
        #expect(effective.sound?.filename == "synth.caf")
    }

    @Test("Time-sensitive device alarm carries the user's selected tone") func timeSensitiveGetsSelectedTone() throws {
        let entry = try #require(AlertCatalogRegistry.lookup(Self.reservoirLow))
        var config = DeviceAlertSeverityConfig(severity: .timeSensitive)
        config.soundFilename = "synth.caf"

        let effective = BaseTrioAlertManager.applyDeviceSeverityConfig(
            config,
            entry: entry,
            to: Self.pluginAlert(Self.reservoirLow)
        )
        #expect(effective.sound == .sound(name: "synth.caf"))
        #expect(effective.interruptionLevel == .timeSensitive)
    }

    @Test("Play Sound off yields a silent alarm") func playSoundOffSilences() throws {
        let entry = try #require(AlertCatalogRegistry.lookup(Self.patchEmpty))
        var config = DeviceAlertSeverityConfig(severity: .critical)
        config.soundFilename = "synth.caf"
        config.playsSound = false

        let effective = BaseTrioAlertManager.applyDeviceSeverityConfig(
            config,
            entry: entry,
            to: Self.pluginAlert(Self.patchEmpty)
        )
        #expect(effective.sound == nil)
    }

    // MARK: - Override Silence & Focus

    @Test("Override Silence & Focus escalates to .critical") func overrideEscalates() throws {
        let entry = try #require(AlertCatalogRegistry.lookup(Self.reservoirLow))
        #expect(entry.interruptionLevel == .timeSensitive, "Precondition: catalog level")
        var config = DeviceAlertSeverityConfig(severity: .timeSensitive)
        config.overridesSilenceAndDND = true

        let effective = BaseTrioAlertManager.applyDeviceSeverityConfig(
            config,
            entry: entry,
            to: Self.pluginAlert(Self.reservoirLow)
        )
        #expect(effective.interruptionLevel == .critical)
    }

    @Test("Override off keeps the catalog level as the floor") func overrideOffKeepsCatalogLevel() throws {
        let entry = try #require(AlertCatalogRegistry.lookup(Self.patchEmpty))
        #expect(entry.interruptionLevel == .critical, "Precondition: catalog level")
        var config = DeviceAlertSeverityConfig(severity: .critical)
        config.overridesSilenceAndDND = false

        // The toggle escalates only — it must not demote a critical alarm.
        let effective = BaseTrioAlertManager.applyDeviceSeverityConfig(
            config,
            entry: entry,
            to: Self.pluginAlert(Self.patchEmpty)
        )
        #expect(effective.interruptionLevel == .critical)
    }

    @Test("Override off does not promote a Normal-tier alarm") func normalTierNotPromoted() throws {
        let identifier = Alert.Identifier(managerIdentifier: "trio.aps", alertIdentifier: "algorithmError")
        let entry = try #require(AlertCatalogRegistry.lookup(identifier))
        #expect(entry.interruptionLevel == .active, "Precondition: catalog level")
        var config = DeviceAlertSeverityConfig(severity: .normal)
        config.overridesSilenceAndDND = false

        let effective = BaseTrioAlertManager.applyDeviceSeverityConfig(
            config,
            entry: entry,
            to: Self.pluginAlert(identifier)
        )
        #expect(effective.interruptionLevel == .active)
    }

    // MARK: - Enabled / day-night gating

    @Test("Disabled tier resolves to no config, so the alarm is dropped") func disabledTierDrops() {
        var disabled = DeviceAlertSeverityConfig(severity: .timeSensitive, activeOption: .always)
        disabled.isEnabled = false
        let store = Self.makeStore(seed: [disabled])

        #expect(store.config(for: .timeSensitive, at: Date(), isNight: false) == nil)
    }

    @Test("Night variant's tone wins at night") func nightVariantToneWins() throws {
        var always = DeviceAlertSeverityConfig(severity: .critical, activeOption: .always)
        always.soundFilename = "alarm.caf"
        var night = DeviceAlertSeverityConfig(severity: .critical, activeOption: .night)
        night.soundFilename = "synth.caf"
        let store = Self.makeStore(seed: [always, night])

        let config = try #require(store.config(for: .critical, at: Date(), isNight: true))
        let entry = try #require(AlertCatalogRegistry.lookup(Self.patchEmpty))
        let effective = BaseTrioAlertManager.applyDeviceSeverityConfig(
            config,
            entry: entry,
            to: Self.pluginAlert(Self.patchEmpty)
        )
        #expect(effective.sound == .sound(name: "synth.caf"))
    }

    @Test("Selected tones resolve to bundled sound files") func tonesExistInCatalog() {
        #expect(AlarmSoundCatalog.allFilenames.contains("synth.caf"))
        for severity in DeviceAlertSeverity.allCases {
            #expect(
                AlarmSoundCatalog.allFilenames.contains(severity.defaultSoundFilename),
                "Default tone for \(severity) is not a bundled sound"
            )
        }
    }

    // MARK: - Identity preservation

    @Test("Overlay preserves identifier, content and trigger") func overlayPreservesIdentity() throws {
        let entry = try #require(AlertCatalogRegistry.lookup(Self.patchEmpty))
        let issued = Self.pluginAlert(Self.patchEmpty)
        let effective = BaseTrioAlertManager.applyDeviceSeverityConfig(
            DeviceAlertSeverityConfig(severity: .critical),
            entry: entry,
            to: issued
        )
        #expect(effective.identifier == issued.identifier)
        #expect(effective.backgroundContent == issued.backgroundContent)
        #expect(effective.foregroundContent == issued.foregroundContent)
        #expect(effective.trigger == issued.trigger)
    }
}

/// Guards the #1371 regression: alarm tones must be resolvable the way iOS
/// resolves `UNNotificationSoundName` — from the flat top level of the main
/// bundle (or `Library/Sounds`). Shipping them inside a `Sounds/` bundle
/// subdirectory made every notification fall back to the default iOS sound.
@Suite("Trio Alerts: alarm tone bundling") struct AlarmToneBundlingTests {
    @Test("Every catalog tone resolves from the main bundle root") func tonesResolveAtBundleRoot() {
        for filename in AlarmSoundCatalog.allFilenames {
            let resource = (filename as NSString).deletingPathExtension
            let ext = (filename as NSString).pathExtension
            #expect(
                Bundle.main.url(forResource: resource, withExtension: ext) != nil,
                "\(filename) is not at the main bundle root — UNNotificationSound cannot resolve it"
            )
        }
    }

    @Test("critical.caf fallback tone is bundled") func criticalFallbackBundled() {
        #expect(Bundle.main.url(forResource: "critical", withExtension: "caf") != nil)
    }

    @Test("Vendor sounds are namespaced flat, not nested") func vendorSoundsNamespaced() {
        // iOS only looks at the top level of Library/Sounds, so a per-manager
        // subdirectory would never resolve.
        let name = AlertSoundLoader.namespaced("Omnipod", "beep.caf")
        #expect(name == "Omnipod-beep.caf")
        #expect(!name.contains("/"))
    }
}
