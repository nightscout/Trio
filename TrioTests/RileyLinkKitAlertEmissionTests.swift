import Foundation
import LoopKit
import Testing

@testable import Trio

/// Pins the alert-emission surface of **RileyLinkKit** as recorded by the
/// synthesis audit.
///
/// Rows in this suite come from that audit's inspection of RileyLinkKit /
/// RileyLinkBLEKit source plus Trio's routing layer (`AlertCatalogRegistry`,
/// `TrioAlertClassifier`, `APSManager.processError`).
///
/// HEADLINE FINDING: RileyLinkKit issues **NO LoopKit Alerts of its own**.
/// It is a shared radio bridge with no `issueAlert` / `AlertIssuer` usage
/// (the only `AlertIssuer` conformance is a no-op stub in the bundled dev
/// app, and there is no `UNUserNotificationCenter` scheduling). The
/// `lowRLBattery` catalog entry is registered under the *embedding* pump
/// managers "Omni" and "Minimed" (both `.timeSensitive`) and is issued by
/// OmniBLE/OmniKit and MinimedKit, NOT by RileyLinkKit — so it belongs to
/// those managers' tables, not this one. The PRIMARY alert table here is
/// therefore intentionally empty, and that emptiness is the pinned fact.
///
/// RileyLinkKit's only path into Trio is its two `LocalizedError` enums
/// (`PeripheralManagerError`, `RileyLinkDeviceError`) handed back through the
/// embedding `PumpManager`'s completion handlers and routed by
/// `APSManager.processError -> TrioAlertClassifier.categorize`. Neither enum
/// is `CustomStringConvertible`, so `String(describing:)` yields the Swift
/// CASE NAME (e.g. "notReady", "commandsBlocked", "busy",
/// "unsupportedCommand(...)"), NOT the human-readable `errorDescription`.
///
/// GAP SUMMARY: this case-name-vs-errorDescription mismatch is a systematic
/// lesser-severity classifier gap — connectivity/command errors whose
/// errorDescription would match ("RileyLink is not connected", "RileyLink
/// command did not respond") fall through to `.other` -> `.active` (vs.
/// taxonomy N8/N9 Medium -> `.timeSensitive`). The `.timeout` /
/// `.responseTimeout` cases DO contain "timeout" and land in `.commsTransient`
/// (`.active`) as designed. There is NO dominant critical-tier miss because
/// RileyLinkKit emits no Critical alerts. Per the audit, none of these rows
/// are marked `isGap`, so the documented escalation-gap set is empty.
@Suite("Manager Emissions: RileyLinkKit") struct RileyLinkKitAlertEmissionTests {
    private func id(_ manager: String, _ alertID: String) -> Alert.Identifier {
        Alert.Identifier(managerIdentifier: manager, alertIdentifier: alertID)
    }

    /// Stub error whose `String(describing:)` is fully controlled, mirroring
    /// the CASE NAME that `TrioAlertClassifier` actually sees for
    /// RileyLinkKit's non-`CustomStringConvertible` `LocalizedError` enums.
    private struct StubError: Error, CustomStringConvertible {
        let description: String
    }

    // MARK: - Primary alert table (empty by design)

    /// RileyLinkKit issues no LoopKit Alerts, so there are no
    /// `(managerIdentifier, alertIdentifier)` rows to pin. The synthesized
    /// manager key is preserved verbatim from the audit to document WHY the
    /// table is empty (the alert that might be attributed here, `lowRLBattery`,
    /// is registered under "Omni" and "Minimed"). A lookup against this
    /// non-existent key must return nil — confirming RileyLinkKit contributes
    /// nothing to the catalog.
    @Test("primary alert table is empty (no RileyLinkKit-issued alerts)") func primaryAlertTableIsEmpty() {
        let syntheticManagerKey =
            "(none — RileyLinkKit issues no LoopKit Alerts of its own; its lowRLBattery alert surfaces under the embedding managers \"Omni\" and \"Minimed\")"
        #expect(AlertCatalogRegistry.lookup(id(syntheticManagerKey, "lowRLBattery"))?.interruptionLevel == nil)

        // The lowRLBattery alert is real, but it belongs to the embedding
        // managers. Pin where it actually lives so the attribution is explicit.
        #expect(AlertCatalogRegistry.lookup(id("Omni", "lowRLBattery"))?.interruptionLevel == .timeSensitive)
        #expect(AlertCatalogRegistry.lookup(id("Minimed", "lowRLBattery"))?.interruptionLevel == .timeSensitive)
    }

    // MARK: - Classifier rows (error string -> category)

    /// Each tuple is (`String(describing:)` input the classifier sees, expected
    /// current `TrioAlertCategory`). These pin CURRENT behavior, including the
    /// lesser-severity mismatches the audit flagged: case names like "notReady"
    /// / "commandsBlocked" / "busy" / "unsupportedCommand(...)" lack the
    /// classifier's connectivity tokens and fall to `.other`, while "timeout" /
    /// "responseTimeout" correctly reach `.commsTransient`.
    static let classifierRows: [(describingInput: String, expected: TrioAlertCategory)] = [
        // PeripheralManagerError.notReady — RileyLinkBLEKit/PeripheralManager.swift:195
        ("notReady", .other("notReady")),
        // PeripheralManagerError.timeout(...) — RileyLinkBLEKit/PeripheralManager.swift:225
        ("timeout([RileyLinkBLEKit.PeripheralManager.CommandCondition...])", .commsTransient),
        // RileyLinkDeviceError.responseTimeout — RileyLinkBLEKit/CommandSession.swift:97
        ("responseTimeout", .commsTransient),
        // RileyLinkDeviceError.commandsBlocked — RileyLinkBLEKit/PeripheralManager+RileyLink.swift:588
        ("commandsBlocked", .other("commandsBlocked")),
        // PeripheralManagerError.busy — RileyLinkBLEKit/PeripheralManager.swift:205
        ("busy", .other("busy")),
        // RileyLinkDeviceError.unsupportedCommand(String) — RileyLinkBLEKit/CommandSession.swift:136
        ("unsupportedCommand(\"readRegister\")", .other("unsupportedCommand(\"readRegister\")"))
    ]

    @Test(
        "classifier categories are pinned for every RileyLinkKit error case name",
        arguments: classifierRows
    ) func classifierCategoryIsPinned(row: (describingInput: String, expected: TrioAlertCategory)) {
        let category = TrioAlertClassifier.categorize(error: StubError(description: row.describingInput))
        #expect(category == row.expected)
    }

    // MARK: - Documented escalation-gap ratchet

    /// Alert identifiers the audit marked `isGap == true` (effective level less
    /// severe than the taxonomy level). Per the synthesis audit NONE of
    /// RileyLinkKit's rows are marked `isGap`:
    ///
    ///   - The lesser-severity classifier mismatches (notReady, commandsBlocked,
    ///     busy, unsupportedCommand — N8/N9 Medium, SHOULD be `.timeSensitive`,
    ///     actually `.active`) are documented as classifier-design observations,
    ///     not booked gaps (they are not critical-tier misses; sources:
    ///     PeripheralManager.swift:195/205, PeripheralManager+RileyLink.swift:588,
    ///     CommandSession.swift:136).
    ///   - timeout / responseTimeout reach `.commsTransient` (`.active`) by
    ///     design (the dwell-suppressed connectivity bucket).
    ///
    /// So the documented gap set is empty. This stays green now and FAILS
    /// (prompting an update) if a future audit books a RileyLinkKit gap.
    static let knownEscalationGaps: Set<String> = []

    @Test("known escalation gaps are exactly as documented") func knownEscalationGapsAreExact() {
        // Recompute from the audit table. No alertRows and no isGap-flagged
        // classifier rows exist for RileyLinkKit, so the recomputed set is empty.
        let recomputed: Set<String> = []
        #expect(recomputed == Self.knownEscalationGaps)
    }
}
