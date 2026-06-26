import Foundation
import LoopKit
import Testing

@testable import Trio

/// Pins `AlertCatalogRegistry.entries` and the static, exact-match
/// `lookup(_:)` behavior. Pump plugins emit at LoopKit's default
/// (`.timeSensitive`); this table is the sole escalation source. An unknown
/// `(manager, alertId)` returns nil (pass-through). The Omni hex-fault parser
/// is covered separately in `AlertCatalogRegistryOmniFaultTests`.
@Suite("TrioAlert: CatalogRegistry — static exact-match entries") struct AlertCatalogRegistryEntriesTests {
    private func id(_ manager: String, _ alertID: String) -> Alert.Identifier {
        Alert.Identifier(managerIdentifier: manager, alertIdentifier: alertID)
    }

    // MARK: - A: critical entries

    @Test(
        "Critical entries escalate to .critical",
        arguments: [
            ("Omni", "unexpectedAlert"),
            ("Minimed", "PumpReservoirEmpty"),
            ("Dana", "batteryZeroPercent"),
            ("Dana", "pumpError"),
            ("Dana", "occlusion"),
            ("Dana", "shutdown"),
            ("Dana", "emptyReservoir"),
            ("Dana", "checkShaft"),
            // Both spellings are registered: MedtrumKit ships the misspelled
            // "patch-occlussion" (double-s) today; "patch-occlusion" is
            // forward-compat for when the upstream typo is fixed. Both escalate.
            ("Medtrum", "com.nightscout.medtrumkit.patch-occlussion"), // double-s (current MedtrumKit)
            ("Medtrum", "com.nightscout.medtrumkit.patch-occlusion"), // single-s (future MedtrumKit)
            ("Medtrum", "com.nightscout.medtrumkit.patch-fault"),
            ("Medtrum", "com.nightscout.medtrumkit.patch-empty")
        ]
    ) func criticalEntries(manager: String, alertID: String) {
        #expect(AlertCatalogRegistry.lookup(id(manager, alertID))?.interruptionLevel == .critical)
    }

    // MARK: - B: representative .timeSensitive entries

    @Test(
        "Representative entries land at .timeSensitive",
        arguments: [
            ("Omni", "lowReservoir"),
            ("Minimed", "PumpBatteryLow"),
            ("Dana", "lowBattery"),
            ("Dana", "unknown"),
            ("Medtrum", "com.nightscout.medtrumkit.reservoir-low"),
            ("Medtrum", "com.nightscout.medtrumkit.patch-daily-limit")
        ]
    ) func timeSensitiveEntries(manager: String, alertID: String) {
        #expect(AlertCatalogRegistry.lookup(id(manager, alertID))?.interruptionLevel == .timeSensitive)
    }

    // MARK: - C: representative .active entries

    @Test(
        "Representative entries stay at .active",
        arguments: [
            ("Omni", "userPodExpiration"),
            ("Dana", "basalCompare"),
            ("Medtrum", "com.nightscout.medtrumkit.patch-expired")
        ]
    ) func activeEntries(manager: String, alertID: String) {
        #expect(AlertCatalogRegistry.lookup(id(manager, alertID))?.interruptionLevel == .active)
    }

    // MARK: - D: unknown identifiers pass through (nil)

    @Test(
        "Unknown identifiers return nil (pass-through)",
        arguments: [
            ("Dana", "totallyMadeUp"),
            ("NoSuchManager", "lowReservoir"),
            ("", "")
        ]
    ) func unknownReturnsNil(manager: String, alertID: String) {
        #expect(AlertCatalogRegistry.lookup(id(manager, alertID)) == nil)
    }

    // MARK: - E: wrong manager, right alert id → nil

    @Test(
        "Right alert id under the wrong manager returns nil",
        arguments: [
            ("Minimed", "unexpectedAlert"),
            ("Dana", "PumpReservoirEmpty")
        ]
    ) func wrongManagerRightID(manager: String, alertID: String) {
        #expect(AlertCatalogRegistry.lookup(id(manager, alertID)) == nil)
    }

    // MARK: - F: right manager, wrong alert id → nil

    // Dana's occlusion entry is the single-s "occlusion"; the double-s
    // "occlussion" is not a Dana key and must return nil. (The double-s
    // spelling IS a valid key under the Medtrum manager — see test A — so this
    // also confirms entries are scoped per-manager.)
    @Test(
        "Wrong alert id under the right manager returns nil",
        arguments: [
            ("Dana", "occlussion"), // double-s is not a Dana key — must NOT match
            ("Medtrum", "patch-fault"), // missing com.nightscout.medtrumkit. prefix
            ("Omni", "lowReservoir ") // trailing space
        ]
    ) func rightManagerWrongID(manager: String, alertID: String) {
        #expect(AlertCatalogRegistry.lookup(id(manager, alertID)) == nil)
    }

    // MARK: - G: manager-scoped lowRLBattery

    @Test("lowRLBattery resolves per-manager for Omni and Minimed") func lowRLBatteryIsManagerScoped() {
        let omni = AlertCatalogRegistry.lookup(id("Omni", "lowRLBattery"))
        let minimed = AlertCatalogRegistry.lookup(id("Minimed", "lowRLBattery"))
        #expect(omni != nil)
        #expect(minimed != nil)
        #expect(omni?.identifier.managerIdentifier == "Omni")
        #expect(minimed?.identifier.managerIdentifier == "Minimed")
    }

    // MARK: - H: invariant — no duplicate manager+alert keys

    @Test("entries have unique manager+alert identifiers") func entriesHaveUniqueKeys() {
        let keys = Set(AlertCatalogRegistry.entries.map(\.identifier))
        #expect(keys.count == AlertCatalogRegistry.entries.count)
    }
}
