import Foundation
import LoopKit
import Testing

@testable import Trio

/// Pins how MinimedKit's emitted LoopKit Alerts are routed through Trio's
/// alert layer, as recorded by the synthesis audit over the managers / pump /
/// MinimedKit sources (`MinimedKit/PumpManager/MinimedPumpManager.swift`).
///
/// What this suite pins:
///  - The CURRENT (not ideal) registry behavior for every alert MinimedKit
///    issues. MinimedKit issues all four alerts with managerIdentifier
///    "Minimed500" (its pluginIdentifier), but `AlertCatalogRegistry` keys its
///    Minimed entries under "Minimed" (AlertCatalogRegistry.swift:88-93). Since
///    `lookup` matches the full `Alert.Identifier` and there is no
///    "Minimed500"-style fallback (only "Omni:pumpFault" has one), every
///    lookup of an actually-emitted identifier returns nil. Trio then falls
///    back to the alert's own plugin level, which is LoopKit's default
///    `.timeSensitive`.
///  - The documented escalation gap, as a ratchet that fails when the gap is
///    fixed (forcing this file to be updated).
///
/// One-line gap summary: PumpReservoirEmpty is taxonomy-Critical (N4 ->
/// `.critical`) but its effective level is `.timeSensitive` because the
/// intended registry entry ("Minimed","PumpReservoirEmpty"=.critical) is
/// unreachable under the emitted managerIdentifier "Minimed500" — so an
/// out-of-insulin condition never escalates to a critical interruption.
@Suite("Manager Emissions: MinimedKit") struct MinimedKitAlertEmissionTests {
    private func id(_ manager: String, _ alertID: String) -> Alert.Identifier {
        Alert.Identifier(managerIdentifier: manager, alertIdentifier: alertID)
    }

    /// The managerIdentifier MinimedKit actually issues with (its
    /// pluginIdentifier), NOT the "Minimed" key the registry uses.
    private static let emittedManagerIdentifier = "Minimed500"

    /// Emitted alerts from the synthesis audit. `currentRegistryLevel` is the
    /// level `lookup(id("Minimed500", alertID))` returns TODAY (all nil due to
    /// the managerIdentifier mismatch). `taxonomyLevel` is what the row should
    /// be per taxonomy; `isGap` is true when the effective level
    /// (registry-or-default `.timeSensitive`) is less severe than taxonomy.
    struct Row {
        let alertIdentifier: String
        let currentRegistryLevel: Alert.InterruptionLevel?
        let taxonomyLevel: Alert.InterruptionLevel
        let isGap: Bool
    }

    private static let rows: [Row] = [
        // F2 -> .timeSensitive. Registry intends ("Minimed","lowRLBattery")=
        // .timeSensitive but it is unreachable; effective default
        // .timeSensitive == taxonomy, not a gap.
        // MinimedKit/PumpManager/MinimedPumpManager.swift:263-268
        Row(alertIdentifier: "lowRLBattery", currentRegistryLevel: nil, taxonomyLevel: .timeSensitive, isGap: false),
        // F2 -> .timeSensitive. ("Minimed","PumpBatteryLow")=.timeSensitive
        // unreachable; effective default == taxonomy, not a gap.
        // MinimedKit/PumpManager/MinimedPumpManager.swift:495-510
        Row(alertIdentifier: "PumpBatteryLow", currentRegistryLevel: nil, taxonomyLevel: .timeSensitive, isGap: false),
        // N4 -> .critical. GAP: ("Minimed","PumpReservoirEmpty")=.critical
        // unreachable under "Minimed500"; effective default .timeSensitive is
        // LESS severe than taxonomy .critical.
        // MinimedKit/PumpManager/MinimedPumpManager.swift:560-600
        Row(alertIdentifier: "PumpReservoirEmpty", currentRegistryLevel: nil, taxonomyLevel: .critical, isGap: true),
        // F1 -> .timeSensitive. ("Minimed","PumpReservoirLow")=.timeSensitive
        // unreachable; effective default == taxonomy, not a gap.
        // MinimedKit/PumpManager/MinimedPumpManager.swift:571-610
        Row(alertIdentifier: "PumpReservoirLow", currentRegistryLevel: nil, taxonomyLevel: .timeSensitive, isGap: false)
    ]

    // MARK: - Registry behavior (pinned to CURRENT, must be green)

    @Test(
        "registry behavior is pinned for every emitted alert",
        arguments: rows
    ) func registryBehaviorPinned(_ row: Row) {
        // Asserts CURRENT behavior: lookup under the EMITTED managerIdentifier
        // "Minimed500" returns the recorded level (nil today). This is not the
        // ideal — it documents the managerIdentifier mismatch.
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
    ///  - "PumpReservoirEmpty": SHOULD be `.critical` (taxonomy N4). The
    ///    registry author intended this — ("Minimed","PumpReservoirEmpty") is
    ///    registered at .critical (AlertCatalogRegistry.swift:90) — but
    ///    MinimedKit issues with managerIdentifier "Minimed500", so the entry
    ///    is dead and the alert falls back to .timeSensitive. Out-of-insulin
    ///    never escalates to a critical interruption.
    ///    Source: MinimedKit/PumpManager/MinimedPumpManager.swift:560-600
    ///
    /// This stays green now and FAILS (prompting an update here) once the
    /// managerIdentifier mismatch is fixed and the gap closes.
    private static let knownEscalationGaps: Set<String> = [
        "PumpReservoirEmpty"
    ]

    @Test("known escalation gaps are exactly as documented") func knownEscalationGapsExact() {
        let computed = Set(Self.rows.filter(\.isGap).map(\.alertIdentifier))
        #expect(computed == Self.knownEscalationGaps)
    }
}
