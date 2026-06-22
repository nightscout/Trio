import Foundation
import LoopKit
import Testing

@testable import Trio

/// Pins Trio's alert-routing behavior for the **TandemKit** pump plugin.
///
/// Rows are derived from the synthesis audit of the Tandem stack
/// (`TandemCore` / `TandemKit` / `TandemKitUI` / `TandemKitPlugin`; pump:
/// Tandem t:slim X2 / Mobi). The audit's central finding is STRUCTURAL:
/// TandemKit issues **zero** LoopKit Alerts. There is no
/// `issueAlert` / `retractAlert` / `Alert(identifier:)` / `DeviceAlert` /
/// `UNUserNotificationCenter` usage anywhere in the shipping targets
/// (audit.md:7-8, Notes:192), so TandemKit never constructs an
/// `Alert.Identifier` and there is no `(managerIdentifier, alertIdentifier)`
/// pair for Trio to route. The PRIMARY emitted-alert table is therefore empty
/// and `AlertCatalogRegistry` has — and could match — no Tandem entries.
///
/// Every Tandem pump alarm the device surfaces (occlusion N1->Critical;
/// empty/removed cartridge & "No Insulin" N4->Critical; battery-shutdown
/// N5-pump->Critical; temperature/altitude/stuck-button/invalid-date/
/// pump-reset & the non-dismissable Malfunction item N1->Critical;
/// resume-pump / auto-off delivery-stopped N2->Critical; CGM-alert catalog
/// N7->High) is rendered ONLY inside TandemKit's own in-app
/// "Pump notifications" settings list
/// (`NotificationBundle` -> `TandemKitNotificationsView`), which Trio never
/// receives. The `AlertResponseType` description catalog is intercepted in
/// `fetchNotifications` (audit:129,193) and is dead for display, and the lone
/// `didError` call site (`TandemPumpManager.swift:218`) has no callers.
///
/// GAP SUMMARY: the effective interruption level of every taxonomy-Critical
/// Tandem alarm is "never delivered" — strictly less severe than `.critical`.
/// This is broader than a registry-key mismatch: no `Alert.Identifier` is
/// ever issued, so no escalation is possible until upstream TandemKit issues
/// LoopKit Alerts (and adopts `AlertCatalogVendor`, or Trio adds Tandem
/// registry entries). The remediation gap is documented in this suite's prose
/// rather than as table rows, because there are no emitted-alert rows to ratchet.
///
/// The only Tandem signals that DO reach Trio are `PumpManagerError`-wrapped
/// `PumpCommError` / `TandemPumpManagerValidationError` values returned through
/// `PumpManager` dosing/limit/time completion handlers (e.g. `enactTempBasal`
/// -> `APSManager:703` `APSError.pumpError(error)` -> `processError` ->
/// `TrioAlertClassifier.categorize`). These are error-STRING emissions, not
/// Alerts. No classifier rows are pinned here: the TandemKit submodule is not
/// present in Trio-dev and the audit recorded the rendered `errorDescription`
/// text rather than the `String(describing:)` form, so the exact classifier
/// input (a LoopKit `PumpManagerError` enum — not `CustomStringConvertible` —
/// wrapping a `PumpCommError`/validation case) cannot be stated with
/// certainty. Per the SCOPE rule those are omitted rather than guessed.
@Suite("Manager Emissions: TandemKit") struct TandemKitAlertEmissionTests {
    /// TandemKit issues no LoopKit Alerts, so it carries no real
    /// `managerIdentifier`. We keep the audit's verbatim placeholder string so
    /// the (empty) registry-lookup pin documents exactly what was searched.
    private static let managerIdentifier =
        "(none — TandemKit issues no LoopKit Alerts; it uses no Alert.Identifier at all)"

    private func id(_ manager: String, _ alertID: String) -> Alert.Identifier {
        Alert.Identifier(managerIdentifier: manager, alertIdentifier: alertID)
    }

    // MARK: - Emitted alerts (PRIMARY table)

    /// `(alertIdentifier, expectedRegistryLevel)`.
    ///
    /// EMPTY: TandemKit issues no LoopKit Alerts (audit.md:7-8, Notes:192), so
    /// there are no `(managerIdentifier, alertIdentifier)` pairs to pin. If this
    /// table ever gains a row, the audit's structural finding has changed and
    /// this suite's doc comment must be revisited.
    static let alertRows: [(alertID: String, expectedLevel: Alert.InterruptionLevel?)] = []

    @Test(
        "registry behavior is pinned for every emitted alert",
        arguments: alertRows
    ) func registryBehaviorIsPinned(row: (alertID: String, expectedLevel: Alert.InterruptionLevel?)) {
        let identifier = id(Self.managerIdentifier, row.alertID)
        #expect(AlertCatalogRegistry.lookup(identifier)?.interruptionLevel == row.expectedLevel)
    }

    /// Backstop for the empty PRIMARY table: even the audit's verbatim
    /// placeholder manager string resolves to no catalog entry. This pins the
    /// structural fact that TandemKit has no escalatable surface in Trio today.
    @Test("no Tandem alert identifier resolves in the catalog registry") func noTandemEntryInRegistry() {
        #expect(Self.alertRows.isEmpty)
        #expect(AlertCatalogRegistry.lookup(id(Self.managerIdentifier, "anything")) == nil)
    }

    // MARK: - Documented escalation gaps (ratchet)

    /// `alertIdentifier`s of emitted alerts whose EFFECTIVE current level is
    /// less severe than their taxonomy level.
    ///
    /// EMPTY by construction: a gap row requires an emitted alert with an
    /// `Alert.Identifier`, and TandemKit emits none. The Tandem alarms that the
    /// taxonomy rates Critical (occlusion N1, empty/removed cartridge & "No
    /// Insulin" N4, battery-shutdown N5-pump, Malfunction/temperature/altitude/
    /// stuck-button/invalid-date/pump-reset N1, resume-pump / auto-off N2) and
    /// High (CGM-alert catalog N7) never reach Trio at all — they live only in
    /// TandemKit's in-app "Pump notifications" list (`NotificationBundle` ->
    /// `TandemKitNotificationsView`; audit.md:7-8, 129, 192-193). That is a
    /// STRUCTURAL gap (no `Alert.Identifier` is ever issued), strictly broader
    /// than a registry-key mismatch, and is documented in the suite prose
    /// rather than as a ratchetable row. The fix is upstream: TandemKit must
    /// issue LoopKit Alerts and adopt `AlertCatalogVendor` (or Trio must add
    /// Tandem registry entries) before any escalation is possible.
    static let knownEscalationGaps: Set<String> = []

    @Test("known escalation gaps are exactly as documented") func knownEscalationGapsAreExactlyAsDocumented() {
        // Recompute the gap set from the PRIMARY table: a row is a gap when its
        // effective level (registry level if present, else unknown) is missing.
        // With no rows this is empty and matches the documented (empty) set.
        // Should TandemKit ever start issuing Alerts and a row be added with an
        // unescalated level, this recomputed set will diverge from
        // `knownEscalationGaps`, failing the test and prompting an update.
        var computed = Set<String>()
        for row in Self.alertRows where row.expectedLevel != .critical {
            // Placeholder recompute: real gap math would compare against the
            // row's taxonomy level. No rows exist, so the loop never executes.
            computed.insert(row.alertID)
        }
        #expect(computed == Self.knownEscalationGaps)
    }
}
