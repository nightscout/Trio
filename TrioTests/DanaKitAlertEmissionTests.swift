import Foundation
import LoopKit
import Testing

@testable import Trio

/// Pins how DanaKit's emitted LoopKit Alerts are routed through Trio's alert
/// layer, as recorded by the synthesis audit over the managers / pump /
/// DanaKit sources (`DanaKit/Packets/DanaNotifyAlarm.swift`,
/// `DanaKit/PumpManager/PumpManagerAlert.swift`,
/// `DanaKit/PumpManager/DanaKitPumpManager.swift`).
///
/// What this suite pins:
///  - The CURRENT (not ideal) registry behavior for every alert DanaKit
///    issues. Unlike MinimedKit, DanaKit issues all 15 `PumpManagerAlert`
///    cases via `delegate.issueAlert` with managerIdentifier "Dana", which
///    MATCHES the registry key (AlertCatalogRegistry.swift:99-115). Every
///    emission therefore resolves to a registry `CatalogEntry` and is
///    overridden to that entry's interruptionLevel; the plugin itself sets no
///    interruptionLevel, so without a registry hit they would fall back to
///    LoopKit's default `.timeSensitive`.
///  - The documented escalation gaps, as a ratchet that fails when a gap is
///    fixed (forcing this file to be updated).
///
/// No classifier rows: every `DanaKitPumpManagerError` reaching
/// `APSManager.processError` is wrapped in LoopKit's `PumpManagerError` before
/// leaving the completion handler, so the exact `String(describing:)` input is
/// the wrapping, not the Dana case name. That input cannot be stated from the
/// synthesis audit alone, so classifier rows are omitted rather than guessed.
///
/// One-line gap summary: three taxonomy-Critical emissions are
/// under-escalated by the registry — `basalMax` and `dailyMax` (N2 Delivery
/// Suspended/Stopped -> `.critical`) are registered `.active`, and `unknown`
/// (N1 Hardware Fault catch-all -> `.critical`) is registered `.timeSensitive`
/// — so a daily/basal hard stop or an unrecognized pump alarm reaches the user
/// below critical.
@Suite("Manager Emissions: DanaKit") struct DanaKitAlertEmissionTests {
    private func id(_ manager: String, _ alertID: String) -> Alert.Identifier {
        Alert.Identifier(managerIdentifier: manager, alertIdentifier: alertID)
    }

    /// The managerIdentifier DanaKit actually issues with, which matches the
    /// registry's "Dana" key (so lookups resolve, unlike MinimedKit).
    private static let emittedManagerIdentifier = "Dana"

    /// Emitted alerts from the synthesis audit. `currentRegistryLevel` is the
    /// level `lookup(id("Dana", alertID))` returns TODAY. `taxonomyLevel` is
    /// what the row should be per taxonomy; `isGap` is true when the effective
    /// level (the registry level here, since all "Dana" lookups resolve) is
    /// less severe than taxonomy.
    struct Row {
        let alertIdentifier: String
        let currentRegistryLevel: Alert.InterruptionLevel?
        let taxonomyLevel: Alert.InterruptionLevel
        let isGap: Bool
    }

    private static let rows: [Row] = [
        // N5-pump -> .critical. Registry .critical matches taxonomy.
        // DanaKit/Packets/DanaNotifyAlarm.swift:11
        Row(alertIdentifier: "batteryZeroPercent", currentRegistryLevel: .critical, taxonomyLevel: .critical, isGap: false),
        // N1 Hardware Fault -> .critical. Registry .critical matches.
        // DanaKit/Packets/DanaNotifyAlarm.swift:12
        Row(alertIdentifier: "pumpError", currentRegistryLevel: .critical, taxonomyLevel: .critical, isGap: false),
        // N1 -> .critical. Registry .critical matches.
        // DanaKit/Packets/DanaNotifyAlarm.swift:13
        Row(alertIdentifier: "occlusion", currentRegistryLevel: .critical, taxonomyLevel: .critical, isGap: false),
        // F2 Battery Low (High) -> .timeSensitive. Registry .timeSensitive matches.
        // DanaKit/Packets/DanaNotifyAlarm.swift:14
        Row(alertIdentifier: "lowBattery", currentRegistryLevel: .timeSensitive, taxonomyLevel: .timeSensitive, isGap: false),
        // N2 Delivery Suspended -> .critical. Registry .critical matches.
        // DanaKit/Packets/DanaNotifyAlarm.swift:15
        Row(alertIdentifier: "shutdown", currentRegistryLevel: .critical, taxonomyLevel: .critical, isGap: false),
        // N14 Informational/Status -> .active. Registry .active matches.
        // DanaKit/Packets/DanaNotifyAlarm.swift:16
        Row(alertIdentifier: "basalCompare", currentRegistryLevel: .active, taxonomyLevel: .active, isGap: false),
        // N14 -> .active. Registry .active matches. Codes 0x07/0xFF both map here.
        // DanaKit/Packets/DanaNotifyAlarm.swift:17
        Row(alertIdentifier: "bloodSugarMeasure", currentRegistryLevel: .active, taxonomyLevel: .active, isGap: false),
        // F1 Insulin Supply Low (High) -> .timeSensitive. Registry .timeSensitive
        // matches. Codes 0x08/0xFE both map here.
        // DanaKit/Packets/DanaNotifyAlarm.swift:19
        Row(
            alertIdentifier: "remainingInsulinLevel",
            currentRegistryLevel: .timeSensitive,
            taxonomyLevel: .timeSensitive,
            isGap: false
        ),
        // N4 Reservoir Empty -> .critical. Registry .critical matches.
        // DanaKit/Packets/DanaNotifyAlarm.swift:21
        Row(alertIdentifier: "emptyReservoir", currentRegistryLevel: .critical, taxonomyLevel: .critical, isGap: false),
        // N1 Hardware Fault -> .critical. Registry .critical matches.
        // DanaKit/Packets/DanaNotifyAlarm.swift:22
        Row(alertIdentifier: "checkShaft", currentRegistryLevel: .critical, taxonomyLevel: .critical, isGap: false),
        // N2 Delivery Suspended/Stopped -> .critical. GAP: registry registers
        // .active, which is LESS severe than taxonomy .critical.
        // DanaKit/Packets/DanaNotifyAlarm.swift:23
        Row(alertIdentifier: "basalMax", currentRegistryLevel: .active, taxonomyLevel: .critical, isGap: true),
        // N2 -> .critical. GAP: registry registers .active, LESS severe than
        // taxonomy .critical.
        // DanaKit/Packets/DanaNotifyAlarm.swift:24
        Row(alertIdentifier: "dailyMax", currentRegistryLevel: .active, taxonomyLevel: .critical, isGap: true),
        // N14 Informational/Status -> .active. Registry .active matches.
        // DanaKit/Packets/DanaNotifyAlarm.swift:25
        Row(alertIdentifier: "bloodSugarCheckMiss", currentRegistryLevel: .active, taxonomyLevel: .active, isGap: false),
        // N1 Hardware Fault catch-all for unmapped alarm codes -> .critical.
        // GAP: registry registers .timeSensitive, LESS severe than taxonomy
        // .critical, so an unrecognized pump alarm reaches the user below
        // critical.
        // DanaKit/Packets/DanaNotifyAlarm.swift:29
        Row(alertIdentifier: "unknown", currentRegistryLevel: .timeSensitive, taxonomyLevel: .critical, isGap: true),
        // N10 Authentication/Security -> .timeSensitive. Registry .timeSensitive
        // matches. DEAD CASE: defined with full copy but never constructed/fired
        // via issueAlert (the equivalent text is an ad hoc SwiftUI string at
        // DanaKitScanViewModel.swift:77, which Trio never receives). Listed for
        // completeness; no gap if it were ever fired.
        // DanaKit/PumpManager/PumpManagerAlert.swift:18
        Row(alertIdentifier: "ble5InvalidKeys", currentRegistryLevel: .timeSensitive, taxonomyLevel: .timeSensitive, isGap: false)
    ]

    // MARK: - Registry behavior (pinned to CURRENT, must be green)

    @Test(
        "registry behavior is pinned for every emitted alert",
        arguments: rows
    ) func registryBehaviorPinned(_ row: Row) {
        // Asserts CURRENT behavior: lookup under the EMITTED managerIdentifier
        // "Dana" returns the recorded level. All Dana lookups resolve (the
        // managerIdentifier matches the registry key); this documents the
        // level the registry overrides each emission to today, not the ideal.
        #expect(
            AlertCatalogRegistry.lookup(
                id(Self.emittedManagerIdentifier, row.alertIdentifier)
            )?.interruptionLevel == row.currentRegistryLevel
        )
    }

    // MARK: - Known escalation gaps (ratchet)

    /// AlertIdentifiers whose effective level is LESS severe than their
    /// taxonomy level today. Documented expectation per identifier:
    ///
    ///  - "basalMax": SHOULD be `.critical` (taxonomy N2 Delivery
    ///    Suspended/Stopped). Registry registers it `.active`
    ///    (AlertCatalogRegistry.swift:110). A basal hard stop reaches the user
    ///    below critical.
    ///    Source: DanaKit/Packets/DanaNotifyAlarm.swift:23
    ///
    ///  - "dailyMax": SHOULD be `.critical` (taxonomy N2). Registry registers
    ///    it `.active` (AlertCatalogRegistry.swift:111). A daily-insulin hard
    ///    stop reaches the user below critical.
    ///    Source: DanaKit/Packets/DanaNotifyAlarm.swift:24
    ///
    ///  - "unknown": SHOULD be `.critical` (taxonomy N1 Hardware Fault). This
    ///    is the catch-all for unmapped pump alarm codes; registry registers it
    ///    `.timeSensitive` (AlertCatalogRegistry.swift:114), so an unrecognized
    ///    pump alarm reaches the user below critical.
    ///    Source: DanaKit/Packets/DanaNotifyAlarm.swift:29
    ///
    /// (basalMax/dailyMax carry warning-style copy — "contact your distributer
    /// to increase the limit" — so the N2 classification itself may warrant
    /// review; as mapped per classified.md they are gaps.)
    ///
    /// This stays green now and FAILS (prompting an update here) once a gap is
    /// closed in the registry.
    private static let knownEscalationGaps: Set<String> = [
        "basalMax",
        "dailyMax",
        "unknown"
    ]

    @Test("known escalation gaps are exactly as documented") func knownEscalationGapsExact() {
        let computed = Set(Self.rows.filter(\.isGap).map(\.alertIdentifier))
        #expect(computed == Self.knownEscalationGaps)
    }
}
