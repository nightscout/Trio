import Foundation
import LoopKit
import Testing

@testable import Trio

/// Pins `AlertCatalogRegistry.lookup` behavior for Tandem identifiers.
/// `TandemPumpManager` builds `Alert.Identifier` from
/// `NotificationItem.stableIdentifier` — `<category>.<slug>.<bit>`, or
/// `malfunction.<aamId>` — so the bit position is part of every identifier and
/// an exact table match never hits. The registry keys on the
/// `<category>.<slug>` prefix and falls back to `<category>.other`.
@Suite("TrioAlert: CatalogRegistry — Tandem slug resolver") struct AlertCatalogRegistryTandemTests {
    private func tandemID(_ alertID: String) -> Alert.Identifier {
        Alert.Identifier(managerIdentifier: "Tandem", alertIdentifier: alertID)
    }

    @Test(
        "Alarms escalate to critical regardless of bit position",
        arguments: [
            "alarm.occlusion.2",
            "alarm.occlusion.17", // same condition, alternate firmware bit
            "alarm.emptyCartridge.4",
            "alarm.cartridgeRemoved.34",
            "alarm.batteryShutdown.9",
            "alarm.resumePump.6",
            "malfunction.128"
        ]
    ) func alarmsAreCritical(alertID: String) {
        #expect(AlertCatalogRegistry.lookup(tandemID(alertID))?.interruptionLevel == .critical)
    }

    @Test("Occlusion resolves to the shared occlusion concept") func occlusionConcept() {
        let entry = AlertCatalogRegistry.lookup(tandemID("alarm.occlusion.2"))
        #expect(entry?.concept == .occlusion)
        #expect(entry?.title == "Occlusion")
        #expect(entry?.category == "Delivery")
    }

    @Test("Empty cartridge collapses onto reservoirEmpty") func emptyCartridgeConcept() {
        #expect(AlertCatalogRegistry.lookup(tandemID("alarm.emptyCartridge.4"))?.concept == .reservoirEmpty)
    }

    @Test(
        "Alerts land at timeSensitive",
        arguments: [
            "alert.lowInsulin.1",
            "alert.lowPower.3",
            "alert.incompleteBolus.11",
            "alert.connectionError.24"
        ]
    ) func alertsAreTimeSensitive(alertID: String) {
        #expect(AlertCatalogRegistry.lookup(tandemID(alertID))?.interruptionLevel == .timeSensitive)
    }

    @Test(
        "Informational alerts stay at active",
        arguments: ["alert.devicePaired.63", "alert.usbConnection.2", "alert.button.26"]
    ) func informationalAlertsAreActive(alertID: String) {
        #expect(AlertCatalogRegistry.lookup(tandemID(alertID))?.interruptionLevel == .active)
    }

    /// A firmware that adds a notification bit mints a slug this table has never seen
    /// ("other", or a slug added upstream). It must still land in its category's tier rather
    /// than bypassing the Device Alarms configuration.
    @Test("Unmapped slugs fall back to the category entry") func unmappedSlugFallsBackToCategory() {
        let alarm = AlertCatalogRegistry.lookup(tandemID("alarm.other.99"))
        #expect(alarm?.interruptionLevel == .critical)
        #expect(alarm?.title == "Pump Alarm")

        let futureAlarm = AlertCatalogRegistry.lookup(tandemID("alarm.someFutureCondition.99"))
        #expect(futureAlarm?.interruptionLevel == .critical)

        let alert = AlertCatalogRegistry.lookup(tandemID("alert.someFutureCondition.42"))
        #expect(alert?.interruptionLevel == .timeSensitive)
        #expect(alert?.title == "Pump Alert")
    }

    /// TandemKit's pre-slug identifiers were `<category>.<bit>`. The reconciler retracts and
    /// re-issues those, but one can still be in flight from a persisted set at upgrade time.
    @Test("Legacy pre-slug identifiers resolve by category") func legacyIdentifierResolves() {
        #expect(AlertCatalogRegistry.lookup(tandemID("alarm.2"))?.interruptionLevel == .critical)
    }

    /// Snooze and same-tier dismissal key off `entry.identifier`, so the resolver has to hand
    /// back the identifier it was given, not the catalog's prefix template.
    @Test("Resolved entry carries the incoming identifier") func entryCarriesIncomingIdentifier() {
        let identifier = tandemID("alarm.occlusion.2")
        #expect(AlertCatalogRegistry.lookup(identifier)?.identifier == identifier)
    }

    /// CGM alert forwarding is opt-in and duplicates Trio's own glucose alarms, so Tandem's
    /// CGM alerts are deliberately uncatalogued and pass through at the level TandemKit set.
    @Test(
        "CGM alerts pass through uncatalogued",
        arguments: ["cgmAlert.high.4", "cgmAlert.sensorExpiring.12", "cgmAlert.other.7"]
    ) func cgmAlertsPassThrough(alertID: String) {
        #expect(AlertCatalogRegistry.lookup(tandemID(alertID)) == nil)
    }

    /// The prefix templates are real catalog entries, so they also resolve on their own. That
    /// costs nothing — `stableIdentifier` always appends the bit, so TandemKit cannot mint a
    /// bare prefix — and it keeps Tandem's concepts visible in the Device Alarms editor, which
    /// walks `entries` rather than calling `lookup`.
    @Test(
        "Prefix templates are themselves catalog entries",
        arguments: ["alarm.occlusion", "malfunction"]
    )  func templatesResolveDirectly(alertID: String) {
        #expect(AlertCatalogRegistry.lookup(tandemID(alertID))?.interruptionLevel == .critical)
    }

    @Test(
        "Neither a template nor a bit-suffixed slug returns nil",
        arguments: ["alarm", "", "alert.", "alarm.occlusion.x"]
    ) func unresolvableIdentifierReturnsNil(alertID: String) {
        #expect(AlertCatalogRegistry.lookup(tandemID(alertID)) == nil)
    }

    /// The plugin identifier is "TandemPumpManager"; alerts are issued under
    /// `TandemPumpManager.managerIdentifier`, which is "Tandem". Only the latter resolves.
    @Test("Tandem slugs under another manager return nil") func wrongManagerReturnsNil() {
        let identifier = Alert.Identifier(
            managerIdentifier: "TandemPumpManager",
            alertIdentifier: "alarm.occlusion.2"
        )
        #expect(AlertCatalogRegistry.lookup(identifier) == nil)
    }
}
