import Foundation
import LoopKit
import Testing

@testable import Trio

// MARK: - Manager Emissions: OmnipodKit

//
// This suite PINS the current alert-routing behavior for every OmnipodKit
// (managerIdentifier "Omni", plus the pod-fault channel "Omni:pumpFault")
// emission that actually reaches Trio. Rows come from the synthesis audit of
// the managers/pump OmnipodKit sources (PumpManagerAlert.swift, OmniPumpManager.swift,
// FaultEventCode.swift) cross-referenced against Trio's AlertCatalogRegistry and
// TrioAlertCategory routing.
//
// Two emission channels reach Trio:
//   1. LoopKit Alerts issued via issueAlert (Alert.Identifier carries
//      managerIdentifier/alertIdentifier). TrioAlertManager.issueAlert OVERRIDES the
//      issued interruptionLevel with AlertCatalogRegistry.lookup(...)'s level when a
//      (managerIdentifier, alertIdentifier) entry is found, else falls back to the
//      plugin's own level. This is the PRIMARY table below.
//   2. PumpManager errors handed back through completion handlers that
//      APSManager.processError routes through TrioAlertClassifier.categorize(error:)
//      (ordered substring match over String(describing: error).lowercased()).
//
// The two tests that assert CURRENT behavior (registry pin, classifier pin) MUST stay
// green. The gap-ratchet test documents the known under-escalations and stays green
// until someone fixes a gap, at which point it FAILS to prompt updating this file.
//
// GAP SUMMARY: Several taxonomy-Critical emissions reach Trio at a sub-critical
// effective level. The dominant gap is end-of-life / suspend escalation:
//   - podExpiring (N6-pump, 72h "Pod Expired") registered .timeSensitive.
//   - suspendEnded (N2, delivery suspended -> "Resume Insulin") registered .timeSensitive.
//   - pod-fault 0x1C exceededMaximumPodLife80Hrs (N6-pump, 80h hard stop, delivery
//     stopped) mapped .timeSensitive by omniPodFaultEntry.
//   - userPodExpiration (F3) registered .active (minor under-escalation vs .timeSensitive).
// Classifier-channel gaps: podSuspended, noResponse, podNotConnected, unfinalizedBolus
// all land at .active where taxonomy wants .timeSensitive.

@Suite("Manager Emissions: OmnipodKit") struct OmnipodKitAlertEmissionTests {
    // MARK: Helpers

    private func id(_ manager: String, _ alertID: String) -> Alert.Identifier {
        Alert.Identifier(managerIdentifier: manager, alertIdentifier: alertID)
    }

    /// Feeds a known String(describing:) value through the same substring classifier
    /// APSManager.processError uses. CustomStringConvertible makes String(describing:)
    /// return exactly `description`, matching the case-name shape of a real Swift error enum.
    private struct StubError: Error, CustomStringConvertible {
        let description: String
    }

    // MARK: - Registry pin (PRIMARY LoopKit-Alert table)

    //
    // (manager, alertIdentifier, expected current registry interruptionLevel or nil).
    // "Omni:pumpFault" rows resolve through omniPodFaultEntry's bounded hex parser.
    // These assert CURRENT behavior, NOT the taxonomy-ideal level.

    static let registryRows: [(manager: String, alertID: String, level: Alert.InterruptionLevel?)] = [
        // managerIdentifier "Omni" — static omniEntries table
        ("Omni", "podExpireImminent", .timeSensitive),
        ("Omni", "userPodExpiration", .active),
        ("Omni", "lowReservoir", .timeSensitive),
        ("Omni", "suspendEnded", .timeSensitive),
        ("Omni", "podExpiring", .timeSensitive),
        ("Omni", "unexpectedAlert", .critical),
        ("Omni", "timeOffsetChangeDetected", .active),
        ("Omni", "lowRLBattery", .timeSensitive),
        // managerIdentifier "Omni:pumpFault" — omniPodFaultEntry hex-code mapping
        ("Omni:pumpFault", "Fault Event Code 0x14: occluded", .critical),
        ("Omni:pumpFault", "Fault Event Code 0x18: reservoirEmpty", .critical),
        ("Omni:pumpFault", "Fault Event Code 0x1C: exceededMaximumPodLife80Hrs", .timeSensitive),
        ("Omni:pumpFault", "Fault Event Code 0xNN: <other>", .critical)
    ]

    @Test(
        "registry behavior is pinned for every emitted alert",
        arguments: registryRows
    ) func registryLevelIsPinned(_ row: (
        manager: String,
        alertID: String,
        level: Alert.InterruptionLevel?
    )) {
        let entry = AlertCatalogRegistry.lookup(id(row.manager, row.alertID))
        #expect(entry?.interruptionLevel == row.level)
    }

    // MARK: - Classifier pin (PumpManager errors via APSManager.processError)

    //
    // (String(describing: error), expected current TrioAlertCategory). Asserts CURRENT
    // substring-match behavior, NOT taxonomy-ideal. Note podSuspended/unfinalizedBolus
    // fall through to .other (no matching rule) and are .active.

    static let classifierRows: [(describing: String, category: TrioAlertCategory)] = [
        ("podFault(OmnipodKit.FaultEventCode(...))", .hardwareFault),
        ("podSuspended", .other("podSuspended")),
        ("unacknowledgedCommandPending", .deliveryUncertain),
        ("noResponse", .commsTransient),
        ("podNotConnected", .commsTransient),
        ("unfinalizedBolus", .other("unfinalizedBolus"))
    ]

    @Test(
        "classifier behavior is pinned for every routed error",
        arguments: classifierRows
    ) func classifierCategoryIsPinned(_ row: (describing: String, category: TrioAlertCategory)) {
        let category = TrioAlertClassifier.categorize(error: StubError(description: row.describing))
        #expect(category == row.category)
    }

    // MARK: - Documented escalation-gap ratchet

    //
    // Each entry is an emission whose EFFECTIVE current level is LESS severe than its
    // taxonomy level. Recorded here verbatim with the taxonomy level it SHOULD have and
    // why. The test below recomputes the gap set from the pinned tables + taxonomy and
    // asserts it equals this documented set. Fixing a gap (raising its level) shrinks the
    // recomputed set and FAILS this test, forcing an update here.

    static let knownEscalationGaps: Set<String> = [
        // LoopKit-Alert (registry) gaps — keyed by alertIdentifier
        // userPodExpiration: F3 -> SHOULD be .timeSensitive; registry .active.
        //   PumpManagerAlert.swift:42,69 / AlertCatalogRegistry.swift:72
        "userPodExpiration",
        // suspendEnded: N2 (delivery suspended/stopped, "Resume Insulin") -> SHOULD be
        //   .critical; registry .timeSensitive. PumpManagerAlert.swift:52,81,124 /
        //   AlertCatalogRegistry.swift:77
        "suspendEnded",
        // podExpiring: N6-pump (72h "Pod Expired", delivery ending) -> SHOULD be .critical;
        //   registry .timeSensitive. PumpManagerAlert.swift:44,71 / AlertCatalogRegistry.swift:73
        "podExpiring",
        // pod-fault 0x1C exceededMaximumPodLife80Hrs: N6-pump (80h hard stop, delivery
        //   stopped) -> SHOULD be .critical; omniPodFaultEntry returns .timeSensitive.
        //   FaultEventCode.swift:650,659 / AlertCatalogRegistry.swift:43-47
        "Fault Event Code 0x1C: exceededMaximumPodLife80Hrs",
        // Classifier-channel gaps — keyed by String(describing: error)
        // podSuspended: N9 (Medium) -> SHOULD be .timeSensitive; .other -> .active.
        //   PodCommsSession.swift:80 / TrioAlertCategory.swift:173
        "podSuspended",
        // noResponse: N8 (Medium) -> SHOULD be .timeSensitive; .commsTransient -> .active.
        //   PodCommsSession.swift:56 / TrioAlertCategory.swift:167-171
        "noResponse",
        // podNotConnected: N8 (Medium) -> SHOULD be .timeSensitive; .commsTransient -> .active.
        //   PodCommsSession.swift:72 / TrioAlertCategory.swift:167
        "podNotConnected",
        // unfinalizedBolus: N9 (Medium) -> SHOULD be .timeSensitive; .other -> .active.
        //   PodCommsSession.swift:74 / TrioAlertCategory.swift:173
        "unfinalizedBolus"
    ]

    // The taxonomy-required minimum level for each gap row, used to recompute the gap set.
    // (identifier, taxonomy-required level).
    static let gapTaxonomyRequirements: [(identifier: String, required: Alert.InterruptionLevel)] = [
        ("userPodExpiration", .timeSensitive),
        ("suspendEnded", .critical),
        ("podExpiring", .critical),
        ("Fault Event Code 0x1C: exceededMaximumPodLife80Hrs", .critical),
        ("podSuspended", .timeSensitive),
        ("noResponse", .timeSensitive),
        ("podNotConnected", .timeSensitive),
        ("unfinalizedBolus", .timeSensitive)
    ]

    /// Numeric severity for comparison: .active < .timeSensitive < .critical.
    private func severity(_ level: Alert.InterruptionLevel) -> Int {
        switch level {
        case .active: return 0
        case .timeSensitive: return 1
        case .critical: return 2
        @unknown default: return -1
        }
    }

    /// Resolves the EFFECTIVE current level of a gap-candidate identifier from the pinned
    /// tables: registry entry (LoopKit-Alert rows) or classifier category interruptionLevel.
    private func effectiveLevel(for identifier: String) -> Alert.InterruptionLevel? {
        // LoopKit-Alert rows (match by alertIdentifier across both manager keys).
        if let row = Self.registryRows.first(where: { $0.alertID == identifier }) {
            return AlertCatalogRegistry.lookup(id(row.manager, row.alertID))?.interruptionLevel
        }
        // Classifier rows (match by String(describing:)).
        if let row = Self.classifierRows.first(where: { $0.describing == identifier }) {
            return TrioAlertClassifier.categorize(error: StubError(description: row.describing)).interruptionLevel
        }
        return nil
    }

    @Test("known escalation gaps are exactly as documented") func knownGapsAreExactlyAsDocumented() {
        var recomputed: Set<String> = []
        for requirement in Self.gapTaxonomyRequirements {
            // Assume .timeSensitive if effective level is somehow unresolved (none expected).
            let effective = effectiveLevel(for: requirement.identifier) ?? .timeSensitive
            if severity(effective) < severity(requirement.required) {
                recomputed.insert(requirement.identifier)
            }
        }
        #expect(recomputed == Self.knownEscalationGaps)
    }
}
