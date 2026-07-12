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

@Suite("Trio Alert Emission: OmnipodKit") struct OmnipodKitAlertEmissionTests {
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

// MARK: - Message Classification: OmnipodKit

//
// SPEC. In production, APSManager.processError hands the caught Swift error to
// TrioAlertClassifier.categorize(error:), which classifies over
// String(describing: error).lowercased() — i.e. the ERROR CASE NAME shape
// (e.g. "podSuspended", "unacknowledgedCommandPending"), NOT the user-facing
// display text. This suite instead catalogs every reportable OmnipodKit message
// — the alertTitle/alertBody/errorMessage/notificationTitle/validation strings a
// user actually sees — keyed by its emitting identifier, and PINS how the
// substring classifier would handle that real prose if it were fed verbatim.
//
// Why this matters: the classifier's checks are SPACELESS substrings
// ("podexpired", "reservoirempty", "noresponse", "communication", "fault", ...).
// Natural-language prose contains spaces, so "Pod Expired" (-> "pod expired")
// does NOT contain "podexpired", "Empty Reservoir" does NOT contain
// "emptyreservoir"/"reservoirempty", "No response from pod" does NOT contain
// "noresponse". The overwhelming majority of OmnipodKit prose therefore falls
// through to .other — a large coverage gap relative to the message taxonomy.
// A handful land in a real bucket by accident: any string containing the bare
// token "fault" ("No faults", "Pod Fault: …", "Internal pod fault …") ->
// .hardwareFault; "occlusion"/"occluded" -> .occlusion; "comms"/"communication"
// -> .commsTransient; "timeout" -> .commsTransient; "unacknowledged" ->
// .deliveryUncertain.
//
// Source: managers/pump OmnipodKit (managerIdentifier "Omni"). Per-row sourceRef
// comments cite the emitting file/line. Classifier under test:
// Trio/Sources/Services/Alerts/TrioAlertCategory.swift
// (TrioAlertClassifier.categorize / categorize(pumpError:)).
//
// NOTE on the four rows where this suite's pinned category differs from the audit
// JSON's hand-traced currentCategory: the audit mis-applied the spaceless rule.
// The pins below reflect the ACTUAL classifier output and stay green:
//   - podExpireImminent "Pod Expired / …"      -> .other  (no "podexpired" token; space).
//   - "No faults"                              -> .hardwareFault (contains "fault").
//   - DeactivationError "…communicating…"      -> .other  ("communicating" != "communication").
//   - unableToReachPod "…Communication was…"   -> .commsTransient (contains "communication").
//
// Two @Tests assert CURRENT behavior and MUST stay green:
//   1. each (identifier, message) classifies as pinned.
//   2. the recomputed coverage-gap set equals classifierCoverageGaps.
// The gap ratchet fails the moment the classifier improves (a gap row starts
// hitting a real bucket), forcing this file to be updated.

@Suite("Trio Alert Emission: OmnipodKit — Classification") struct OmnipodKitMessageClassificationTests {
    /// Error whose String(describing:) is exactly `description`, so the substring
    /// classifier matches over the supplied display text verbatim.
    private struct StubError: Error, CustomStringConvertible {
        let description: String
    }

    /// One reportable message: its emitting identifier, the exact user-facing text,
    /// the message role, its taxonomy id, and the pinned classifier category.
    struct Row {
        let identifier: String
        let message: String
        let role: String
        let taxonomy: String
        let expected: TrioAlertCategory
    }

    static let rows: [Row] = [
        // OmnipodKit/OmnipodCommon/PumpManagerAlert.swift:46,73
        Row(
            identifier: "podExpireImminent",
            message: "Pod Expired / Change Pod now. Insulin delivery will stop in 1 hour.",
            role: "alertBody",
            taxonomy: "F3",
            expected: .other("Pod Expired / Change Pod now. Insulin delivery will stop in 1 hour.")
        ),
        // OmnipodKit/OmnipodCommon/PumpManagerAlert.swift:42,69
        Row(
            identifier: "userPodExpiration",
            message: "Pod Expiration Reminder / Pod expires in %1$@.",
            role: "alertTitle",
            taxonomy: "F3",
            expected: .other("Pod Expiration Reminder / Pod expires in %1$@.")
        ),
        // OmnipodKit/OmnipodCommon/PumpManagerAlert.swift:48,77
        Row(
            identifier: "lowReservoir",
            message: "Low Reservoir / %1$@ insulin or less remaining in Pod. Change Pod soon.",
            role: "alertTitle",
            taxonomy: "F1",
            expected: .other("Low Reservoir / %1$@ insulin or less remaining in Pod. Change Pod soon.")
        ),
        // OmnipodKit/OmnipodCommon/PumpManagerAlert.swift:50,79
        Row(
            identifier: "suspendInProgress",
            message: "Suspend In Progress Reminder / Suspend In Progress Reminder",
            role: "alertTitle",
            taxonomy: "N2",
            expected: .other("Suspend In Progress Reminder / Suspend In Progress Reminder")
        ),
        // OmnipodKit/OmnipodCommon/PumpManagerAlert.swift:52,81,124
        Row(
            identifier: "suspendEnded",
            message: "Resume Insulin / The insulin suspension period has ended.\n\nYou can resume delivery from the banner on the home screen or from your pump settings screen. You will be reminded again in 15 minutes.",
            role: "alertBody",
            taxonomy: "N2",
            expected: .other(
                "Resume Insulin / The insulin suspension period has ended.\n\nYou can resume delivery from the banner on the home screen or from your pump settings screen. You will be reminded again in 15 minutes."
            )
        ),
        // OmnipodKit/OmnipodCommon/PumpManagerAlert.swift:52,81,124
        Row(
            identifier: "suspendEnded",
            message: "Suspension time is up. Open the app and resume.",
            role: "alertBody",
            taxonomy: "N2",
            expected: .other("Suspension time is up. Open the app and resume.")
        ),
        // OmnipodKit/OmnipodCommon/PumpManagerAlert.swift:44,71
        Row(
            identifier: "podExpiring",
            message: "Pod Expired / Change Pod now. Pod has been active for 72 hours.",
            role: "alertBody",
            taxonomy: "N6",
            expected: .other("Pod Expired / Change Pod now. Pod has been active for 72 hours.")
        ),
        // OmnipodKit/OmnipodCommon/PumpManagerAlert.swift:54,83
        Row(
            identifier: "finishSetupReminder",
            message: "Pod Pairing Incomplete / Please finish pairing your pod.",
            role: "alertTitle",
            taxonomy: "N14",
            expected: .other("Pod Pairing Incomplete / Please finish pairing your pod.")
        ),
        // OmnipodKit/OmnipodCommon/PumpManagerAlert.swift:56,86
        Row(
            identifier: "unexpectedAlert",
            message: "Unexpected Alert / Unexpected Pod Alert #%1@!",
            role: "alertTitle",
            taxonomy: "N1",
            expected: .other("Unexpected Alert / Unexpected Pod Alert #%1@!")
        ),
        // OmnipodKit/OmnipodCommon/PumpManagerAlert.swift:58,88
        Row(
            identifier: "timeOffsetChangeDetected",
            message: "Time Change Detected / The time on your pump is different from the current time. You can review the pump time and and sync to current time in settings.",
            role: "alertTitle",
            taxonomy: "N14",
            expected: .other(
                "Time Change Detected / The time on your pump is different from the current time. You can review the pump time and and sync to current time in settings."
            )
        ),
        // OmnipodKit/OmnipodCommon/AlertSlot.swift:101,141
        Row(
            identifier: "PodAlert.autoOff",
            message: "Auto-off",
            role: "errorMessage",
            taxonomy: "N2",
            expected: .other("Auto-off")
        ),
        // OmnipodKit/OmnipodCommon/AlertSlot.swift:108,147
        Row(
            identifier: "PodAlert.shutdownImminent",
            message: "Shutdown imminent",
            role: "errorMessage",
            taxonomy: "F3",
            expected: .other("Shutdown imminent")
        ),
        // OmnipodKit/OmnipodCommon/AlertSlot.swift:113,150
        Row(
            identifier: "PodAlert.expirationReminder",
            message: "Expiration reminder",
            role: "errorMessage",
            taxonomy: "F3",
            expected: .other("Expiration reminder")
        ),
        // OmnipodKit/OmnipodCommon/AlertSlot.swift:116,153
        Row(
            identifier: "PodAlert.lowReservoir",
            message: "Low reservoir",
            role: "errorMessage",
            taxonomy: "F1",
            expected: .other("Low reservoir")
        ),
        // OmnipodKit/OmnipodCommon/AlertSlot.swift:120,156
        Row(
            identifier: "PodAlert.podSuspendedReminder",
            message: "Pod suspended reminder",
            role: "errorMessage",
            taxonomy: "N2",
            expected: .other("Pod suspended reminder")
        ),
        // OmnipodKit/OmnipodCommon/AlertSlot.swift:125,159
        Row(
            identifier: "PodAlert.suspendTimeExpired",
            message: "Suspend time expired",
            role: "errorMessage",
            taxonomy: "N2",
            expected: .other("Suspend time expired")
        ),
        // OmnipodKit/OmnipodCommon/AlertSlot.swift:128,162
        Row(
            identifier: "PodAlert.waitingForPairingReminder",
            message: "Waiting for pairing reminder",
            role: "errorMessage",
            taxonomy: "N14",
            expected: .other("Waiting for pairing reminder")
        ),
        // OmnipodKit/OmnipodCommon/AlertSlot.swift:131,164
        Row(
            identifier: "PodAlert.finishSetupReminder",
            message: "Finish setup reminder",
            role: "errorMessage",
            taxonomy: "N14",
            expected: .other("Finish setup reminder")
        ),
        // OmnipodKit/OmnipodCommon/AlertSlot.swift:134,166
        Row(
            identifier: "PodAlert.expired",
            message: "Pod expired",
            role: "errorMessage",
            taxonomy: "N6",
            expected: .other("Pod expired")
        ),
        // OmnipodKit/OmnipodCommon/FaultEventCode.swift:646,659
        Row(
            identifier: "reservoirEmpty",
            message: "Empty Reservoir / Insulin delivery stopped. Change Pod now.",
            role: "notificationTitle",
            taxonomy: "N4",
            expected: .other("Empty Reservoir / Insulin delivery stopped. Change Pod now.")
        ),
        // OmnipodKit/OmnipodCommon/FaultEventCode.swift:648,659
        Row(
            identifier: "occlusion",
            message: "Occlusion Detected / Insulin delivery stopped. Change Pod now.",
            role: "notificationTitle",
            taxonomy: "N1",
            expected: .occlusion
        ),
        // OmnipodKit/OmnipodCommon/FaultEventCode.swift:650,659
        Row(
            identifier: "exceededMaximumPodLife80Hrs",
            message: "Pod Expired / Insulin delivery stopped. Change Pod now.",
            role: "notificationTitle",
            taxonomy: "N6",
            expected: .other("Pod Expired / Insulin delivery stopped. Change Pod now.")
        ),
        // OmnipodKit/OmnipodCommon/FaultEventCode.swift:652,659
        Row(
            identifier: "criticalPodFault",
            message: "Critical Pod Fault %1$@ / Insulin delivery stopped. Change Pod now.",
            role: "notificationTitle",
            taxonomy: "N1",
            expected: .hardwareFault
        ),
        // OmnipodKit/OmnipodCommon/FaultEventCode.swift:619-640
        Row(
            identifier: "FaultEventCode.localizedDescription",
            message: "No faults",
            role: "errorMessage",
            taxonomy: "N1",
            expected: .hardwareFault
        ),
        // OmnipodKit/OmnipodCommon/FaultEventCode.swift:619-640
        Row(
            identifier: "FaultEventCode.localizedDescription",
            message: "Empty reservoir",
            role: "errorMessage",
            taxonomy: "N1",
            expected: .other("Empty reservoir")
        ),
        // OmnipodKit/OmnipodCommon/FaultEventCode.swift:619-640
        Row(
            identifier: "FaultEventCode.localizedDescription",
            message: "Pod expired",
            role: "errorMessage",
            taxonomy: "N1",
            expected: .other("Pod expired")
        ),
        // OmnipodKit/OmnipodCommon/FaultEventCode.swift:619-640
        Row(
            identifier: "FaultEventCode.localizedDescription",
            message: "Occlusion detected",
            role: "errorMessage",
            taxonomy: "N1",
            expected: .occlusion
        ),
        // OmnipodKit/OmnipodCommon/FaultEventCode.swift:619-640
        Row(
            identifier: "FaultEventCode.localizedDescription",
            message: "Internal pod fault %1$@",
            role: "errorMessage",
            taxonomy: "N1",
            expected: .hardwareFault
        ),
        // OmnipodKit/OmnipodCommon/FaultEventCode.swift:619-640
        Row(
            identifier: "FaultEventCode.localizedDescription",
            message: "Unknown pod fault %1$@",
            role: "errorMessage",
            taxonomy: "N1",
            expected: .hardwareFault
        ),
        // OmnipodKit/PumpManager/PodCommsSession.swift:83
        Row(
            identifier: "PodCommsError.podFault",
            message: "Pod Fault: %1$@",
            role: "errorMessage",
            taxonomy: "N1",
            expected: .hardwareFault
        ),
        // OmnipodKit/PumpManager/PodCommsSession.swift:52
        Row(
            identifier: "PodCommsError.noPodPaired",
            message: "No pod paired",
            role: "errorMessage",
            taxonomy: "N9",
            expected: .other("No pod paired")
        ),
        // OmnipodKit/PumpManager/PodCommsSession.swift:56
        Row(
            identifier: "PodCommsError.noResponse",
            message: "No response from pod",
            role: "errorMessage",
            taxonomy: "N8",
            expected: .other("No response from pod")
        ),
        // OmnipodKit/PumpManager/PodCommsSession.swift:56
        Row(
            identifier: "PodCommsError.noResponse",
            message: "Make sure iPhone is nearby the active pod",
            role: "errorMessage",
            taxonomy: "N8",
            expected: .other("Make sure iPhone is nearby the active pod")
        ),
        // OmnipodKit/PumpManager/PodCommsSession.swift:56
        Row(
            identifier: "PodCommsError.noResponseRL",
            message: "No response from pod",
            role: "errorMessage",
            taxonomy: "N8",
            expected: .other("No response from pod")
        ),
        // OmnipodKit/PumpManager/PodCommsSession.swift:56
        Row(
            identifier: "PodCommsError.noResponseRL",
            message: "Please try repositioning the pod or the RileyLink and try again",
            role: "errorMessage",
            taxonomy: "N8",
            expected: .other("Please try repositioning the pod or the RileyLink and try again")
        ),
        // OmnipodKit/PumpManager/PodCommsSession.swift:58
        Row(
            identifier: "PodCommsError.emptyResponse",
            message: "Empty response from pod",
            role: "errorMessage",
            taxonomy: "N8",
            expected: .other("Empty response from pod")
        ),
        // OmnipodKit/PumpManager/PodCommsSession.swift:60
        Row(
            identifier: "PodCommsError.podAckedInsteadOfReturningResponse",
            message: "Pod sent ack instead of response",
            role: "errorMessage",
            taxonomy: "N8",
            expected: .other("Pod sent ack instead of response")
        ),
        // OmnipodKit/PumpManager/PodCommsSession.swift:60
        Row(
            identifier: "PodCommsError.podAckedInsteadOfReturningResponse",
            message: "Try again",
            role: "errorMessage",
            taxonomy: "N8",
            expected: .other("Try again")
        ),
        // OmnipodKit/PumpManager/PodCommsSession.swift:64
        Row(
            identifier: "PodCommsError.unexpectedResponse",
            message: "Unexpected response from pod",
            role: "errorMessage",
            taxonomy: "N8",
            expected: .other("Unexpected response from pod")
        ),
        // OmnipodKit/PumpManager/PodCommsSession.swift:68
        Row(
            identifier: "PodCommsError.invalidAddress",
            message: "Invalid address 0x%x. Expected 0x%x",
            role: "errorMessage",
            taxonomy: "N8",
            expected: .other("Invalid address 0x%x. Expected 0x%x")
        ),
        // OmnipodKit/PumpManager/PodCommsSession.swift:68
        Row(
            identifier: "PodCommsError.invalidAddress",
            message: "Crosstalk possible. Please move to a new location",
            role: "errorMessage",
            taxonomy: "N8",
            expected: .other("Crosstalk possible. Please move to a new location")
        ),
        // OmnipodKit/PumpManager/PodCommsSession.swift:70
        Row(
            identifier: "PodCommsError.noRileyLinkAvailable",
            message: "No RileyLink available",
            role: "errorMessage",
            taxonomy: "N8",
            expected: .other("No RileyLink available")
        ),
        // OmnipodKit/PumpManager/PodCommsSession.swift:70
        Row(
            identifier: "PodCommsError.noRileyLinkAvailable",
            message: "Make sure your RileyLink is nearby and powered on",
            role: "errorMessage",
            taxonomy: "N8",
            expected: .other("Make sure your RileyLink is nearby and powered on")
        ),
        // OmnipodKit/PumpManager/PodCommsSession.swift:72
        Row(
            identifier: "PodCommsError.podNotConnected",
            message: "Pod not connected",
            role: "errorMessage",
            taxonomy: "N8",
            expected: .other("Pod not connected")
        ),
        // OmnipodKit/PumpManager/PodCommsSession.swift:72
        Row(
            identifier: "PodCommsError.podNotConnected",
            message: "Make sure your pod is nearby and try again",
            role: "errorMessage",
            taxonomy: "N8",
            expected: .other("Make sure your pod is nearby and try again")
        ),
        // OmnipodKit/PumpManager/PodCommsSession.swift:74
        Row(
            identifier: "PodCommsError.unfinalizedBolus",
            message: "Bolus in progress",
            role: "errorMessage",
            taxonomy: "N9",
            expected: .other("Bolus in progress")
        ),
        // OmnipodKit/PumpManager/PodCommsSession.swift:74
        Row(
            identifier: "PodCommsError.unfinalizedBolus",
            message: "Wait for existing bolus to finish, or cancel bolus",
            role: "errorMessage",
            taxonomy: "N9",
            expected: .other("Wait for existing bolus to finish, or cancel bolus")
        ),
        // OmnipodKit/PumpManager/PodCommsSession.swift:76
        Row(
            identifier: "PodCommsError.unfinalizedTempBasal",
            message: "Temp basal in progress",
            role: "errorMessage",
            taxonomy: "N9",
            expected: .other("Temp basal in progress")
        ),
        // OmnipodKit/PumpManager/PodCommsSession.swift:76
        Row(
            identifier: "PodCommsError.unfinalizedTempBasal",
            message: "Wait for existing temp basal to finish, or suspend to cancel",
            role: "errorMessage",
            taxonomy: "N9",
            expected: .other("Wait for existing temp basal to finish, or suspend to cancel")
        ),
        // OmnipodKit/PumpManager/PodCommsSession.swift:80
        Row(
            identifier: "PodCommsError.podSuspended",
            message: "Pod is suspended",
            role: "errorMessage",
            taxonomy: "N9",
            expected: .other("Pod is suspended")
        ),
        // OmnipodKit/PumpManager/PodCommsSession.swift:80
        Row(
            identifier: "PodCommsError.podSuspended",
            message: "Resume delivery",
            role: "errorMessage",
            taxonomy: "N9",
            expected: .other("Resume delivery")
        ),
        // OmnipodKit/PumpManager/PodCommsSession.swift:89
        Row(
            identifier: "PodCommsError.unacknowledgedMessage",
            message: "wrapped error's localizedDescription",
            role: "errorMessage",
            taxonomy: "N3",
            expected: .other("wrapped error's localizedDescription")
        ),
        // OmnipodKit/PumpManager/PodCommsSession.swift:92
        Row(
            identifier: "PodCommsError.unacknowledgedCommandPending",
            message: "Communication issue: Unacknowledged command pending.",
            role: "errorMessage",
            taxonomy: "N3",
            expected: .deliveryUncertain
        ),
        // OmnipodKit/PumpManager/PodCommsSession.swift:93-97
        Row(
            identifier: "PodCommsError.rejectedMessage",
            message: "Command error %1$@: %2$@",
            role: "errorMessage",
            taxonomy: "N9",
            expected: .other("Command error %1$@: %2$@")
        ),
        // OmnipodKit/PumpManager/PodCommsSession.swift:99
        Row(
            identifier: "PodCommsError.podChange",
            message: "Unexpected pod change",
            role: "errorMessage",
            taxonomy: "N12",
            expected: .other("Unexpected pod change")
        ),
        // OmnipodKit/PumpManager/PodCommsSession.swift:99
        Row(
            identifier: "PodCommsError.podChange",
            message: "Please bring only original pod in range or deactivate original pod",
            role: "errorMessage",
            taxonomy: "N12",
            expected: .other("Please bring only original pod in range or deactivate original pod")
        ),
        // OmnipodKit/PumpManager/PodCommsSession.swift:101
        Row(
            identifier: "PodCommsError.activationTimeExceeded",
            message: "Activation time exceeded",
            role: "errorMessage",
            taxonomy: "N12",
            expected: .other("Activation time exceeded")
        ),
        // OmnipodKit/PumpManager/PodCommsSession.swift:103
        Row(
            identifier: "PodCommsError.rssiTooLow",
            message: "Poor signal strength",
            role: "errorMessage",
            taxonomy: "N12",
            expected: .other("Poor signal strength")
        ),
        // OmnipodKit/PumpManager/PodCommsSession.swift:103
        Row(
            identifier: "PodCommsError.rssiTooLow",
            message: "Please reposition the RileyLink relative to the pod",
            role: "errorMessage",
            taxonomy: "N12",
            expected: .other("Please reposition the RileyLink relative to the pod")
        ),
        // OmnipodKit/PumpManager/PodCommsSession.swift:105
        Row(
            identifier: "PodCommsError.rssiTooHigh",
            message: "Signal strength too high",
            role: "errorMessage",
            taxonomy: "N12",
            expected: .other("Signal strength too high")
        ),
        // OmnipodKit/PumpManager/PodCommsSession.swift:105
        Row(
            identifier: "PodCommsError.rssiTooHigh",
            message: "Please reposition the RileyLink further from the pod",
            role: "errorMessage",
            taxonomy: "N12",
            expected: .other("Please reposition the RileyLink further from the pod")
        ),
        // OmnipodKit/PumpManager/PodCommsSession.swift:107
        Row(
            identifier: "PodCommsError.diagnosticMessage",
            message: "Received resynchronization SQN for the second time",
            role: "errorMessage",
            taxonomy: "N15",
            expected: .other("Received resynchronization SQN for the second time")
        ),
        // OmnipodKit/PumpManager/PodCommsSession.swift:107
        Row(
            identifier: "PodCommsError.diagnosticMessage",
            message: "Pod type not configured",
            role: "errorMessage",
            taxonomy: "N15",
            expected: .other("Pod type not configured")
        ),
        // OmnipodKit/PumpManager/PodCommsSession.swift:109
        Row(
            identifier: "PodCommsError.podIncompatible",
            message: "Pod version %@ ... not supported",
            role: "errorMessage",
            taxonomy: "N12",
            expected: .other("Pod version %@ ... not supported")
        ),
        // OmnipodKit/PumpManager/PodCommsSession.swift:111
        Row(
            identifier: "PodCommsError.noPodsFound",
            message: "No pods found",
            role: "errorMessage",
            taxonomy: "N12",
            expected: .other("No pods found")
        ),
        // OmnipodKit/PumpManager/PodCommsSession.swift:111
        Row(
            identifier: "PodCommsError.noPodsFound",
            message: "Make sure your pod is filled and nearby",
            role: "errorMessage",
            taxonomy: "N12",
            expected: .other("Make sure your pod is filled and nearby")
        ),
        // OmnipodKit/PumpManager/PodCommsSession.swift:113
        Row(
            identifier: "PodCommsError.tooManyPodsFound",
            message: "Too many pods found",
            role: "errorMessage",
            taxonomy: "N12",
            expected: .other("Too many pods found")
        ),
        // OmnipodKit/PumpManager/PodCommsSession.swift:113
        Row(
            identifier: "PodCommsError.tooManyPodsFound",
            message: "Move to a new area away from any other pods and try again",
            role: "errorMessage",
            taxonomy: "N12",
            expected: .other("Move to a new area away from any other pods and try again")
        ),
        // OmnipodKit/PumpManager/PodCommsSession.swift:115
        Row(
            identifier: "PodCommsError.setupNotComplete",
            message: "Pod setup is not complete",
            role: "errorMessage",
            taxonomy: "N9",
            expected: .other("Pod setup is not complete")
        ),
        // OmnipodKit/PumpManager/PodCommsSession.swift:117
        Row(
            identifier: "PodCommsError.noCertificateFound",
            message: "No certificate found",
            role: "errorMessage",
            taxonomy: "N10",
            expected: .other("No certificate found")
        ),
        // OmnipodKit/PumpManager/PodCommsSession.swift:117
        Row(
            identifier: "PodCommsError.noCertificateFound",
            message: "Retrieve an Omnipod 5 Pod Certificate to continue.",
            role: "errorMessage",
            taxonomy: "N10",
            expected: .other("Retrieve an Omnipod 5 Pod Certificate to continue.")
        ),
        // OmnipodKit/PumpManager/OmniPumpManager.swift:46
        Row(
            identifier: "OmniPumpManagerError.noPodPaired",
            message: "No pod paired",
            role: "errorMessage",
            taxonomy: "N9",
            expected: .other("No pod paired")
        ),
        // OmnipodKit/PumpManager/OmniPumpManager.swift:46
        Row(
            identifier: "OmniPumpManagerError.noPodPaired",
            message: "Please pair a new pod",
            role: "errorMessage",
            taxonomy: "N9",
            expected: .other("Please pair a new pod")
        ),
        // OmnipodKit/PumpManager/OmniPumpManager.swift:48
        Row(
            identifier: "OmniPumpManagerError.insulinTypeNotConfigured",
            message: "Insulin type not configured",
            role: "validation",
            taxonomy: "N13",
            expected: .other("Insulin type not configured")
        ),
        // OmnipodKit/PumpManager/OmniPumpManager.swift:50
        Row(
            identifier: "OmniPumpManagerError.notReadyForCannulaInsertion",
            message: "Pod is not in a state ready for cannula insertion",
            role: "errorMessage",
            taxonomy: "N12",
            expected: .other("Pod is not in a state ready for cannula insertion")
        ),
        // OmnipodKit/PumpManager/OmniPumpManager.swift:52
        Row(
            identifier: "OmniPumpManagerError.invalidSetting",
            message: "Invalid Setting",
            role: "validation",
            taxonomy: "N13",
            expected: .other("Invalid Setting")
        ),
        // OmnipodKit/PumpManager/OmniPumpManager.swift:54
        Row(
            identifier: "OmniPumpManagerError.podTypeNotConfigured",
            message: "Pod type not configured",
            role: "validation",
            taxonomy: "N13",
            expected: .other("Pod type not configured")
        ),
        // OmnipodKit/PumpManagerUI/Views/OmniSettingsView.swift:749-753
        Row(
            identifier: "OmniSettingsViewAlert.suspendError",
            message: "Failed to Suspend Insulin Delivery",
            role: "alertTitle",
            taxonomy: "N9",
            expected: .other("Failed to Suspend Insulin Delivery")
        ),
        // OmnipodKit/PumpManagerUI/Views/OmniSettingsView.swift:755-759
        Row(
            identifier: "OmniSettingsViewAlert.resumeError",
            message: "Failed to Resume Insulin Delivery",
            role: "alertTitle",
            taxonomy: "N9",
            expected: .other("Failed to Resume Insulin Delivery")
        ),
        // OmnipodKit/PumpManagerUI/Views/OmniSettingsView.swift:761-765
        Row(
            identifier: "OmniSettingsViewAlert.syncTimeError",
            message: "Failed to Set Pump Time",
            role: "alertTitle",
            taxonomy: "N9",
            expected: .other("Failed to Set Pump Time")
        ),
        // OmnipodKit/PumpManagerUI/Views/OmniSettingsView.swift:767-771
        Row(
            identifier: "OmniSettingsViewAlert.cancelManualBasalError",
            message: "Failed to Cancel Manual Basal",
            role: "alertTitle",
            taxonomy: "N9",
            expected: .other("Failed to Cancel Manual Basal")
        ),
        // OmnipodKit/PumpManagerUI/ViewModels/DeactivatePodViewModel.swift:198-214
        Row(
            identifier: "DeactivationError.OmniPumpManagerError",
            message: "There was a problem communicating with the pod. If this problem persists, tap Discard Pod. You can then activate a new Pod.",
            role: "errorMessage",
            taxonomy: "N12",
            expected: .other(
                "There was a problem communicating with the pod. If this problem persists, tap Discard Pod. You can then activate a new Pod."
            )
        ),
        // OmnipodKit/OmnipodCommon/Message.swift:26
        Row(
            identifier: "MessageError.notEnoughData",
            message: "Not enough data",
            role: "errorMessage",
            taxonomy: "N8",
            expected: .other("Not enough data")
        ),
        // OmnipodKit/OmnipodCommon/Message.swift:28
        Row(
            identifier: "MessageError.invalidCrc",
            message: "Invalid CRC",
            role: "errorMessage",
            taxonomy: "N8",
            expected: .other("Invalid CRC")
        ),
        // OmnipodKit/OmnipodCommon/Message.swift:30
        Row(
            identifier: "MessageError.invalidSequence",
            message: "Unexpected message sequence number",
            role: "errorMessage",
            taxonomy: "N8",
            expected: .other("Unexpected message sequence number")
        ),
        // OmnipodKit/OmnipodCommon/Message.swift:32
        Row(
            identifier: "MessageError.invalidAddress",
            message: "Invalid address: (%1$@)",
            role: "errorMessage",
            taxonomy: "N8",
            expected: .other("Invalid address: (%1$@)")
        ),
        // OmnipodKit/OmnipodCommon/Message.swift:34
        Row(
            identifier: "MessageError.parsingError",
            message: "Parsing Error: %1$@ in (%2$@)",
            role: "errorMessage",
            taxonomy: "N8",
            expected: .other("Parsing Error: %1$@ in (%2$@)")
        ),
        // OmnipodKit/OmnipodCommon/Message.swift:36
        Row(
            identifier: "MessageError.unknownValue",
            message: "Unknown Value (%1$@) for type %2$@",
            role: "errorMessage",
            taxonomy: "N8",
            expected: .other("Unknown Value (%1$@) for type %2$@")
        ),
        // OmnipodKit/OmnipodCommon/Message.swift:38
        Row(
            identifier: "MessageError.validationFailed",
            message: "Validation failed: %1$@",
            role: "errorMessage",
            taxonomy: "N8",
            expected: .other("Validation failed: %1$@")
        ),
        // OmnipodKit/Bluetooth/PeripheralManagerError.swift:29
        Row(
            identifier: "PeripheralManagerError.notReady",
            message: "Peripheral Not Ready",
            role: "errorMessage",
            taxonomy: "N8",
            expected: .other("Peripheral Not Ready")
        ),
        // OmnipodKit/Bluetooth/PeripheralManagerError.swift:31
        Row(
            identifier: "PeripheralManagerError.incorrectResponse",
            message: "Incorrect Response",
            role: "errorMessage",
            taxonomy: "N8",
            expected: .other("Incorrect Response")
        ),
        // OmnipodKit/Bluetooth/PeripheralManagerError.swift:33
        Row(
            identifier: "PeripheralManagerError.timeout",
            message: "Timeout",
            role: "errorMessage",
            taxonomy: "N8",
            expected: .commsTransient
        ),
        // OmnipodKit/Bluetooth/PeripheralManagerError.swift:35
        Row(
            identifier: "PeripheralManagerError.emptyValue",
            message: "Empty Value",
            role: "errorMessage",
            taxonomy: "N8",
            expected: .other("Empty Value")
        ),
        // OmnipodKit/Bluetooth/PeripheralManagerError.swift:37
        Row(
            identifier: "PeripheralManagerError.unknownCharacteristic",
            message: "Unknown Characteristic",
            role: "errorMessage",
            taxonomy: "N8",
            expected: .other("Unknown Characteristic")
        ),
        // OmnipodKit/Bluetooth/PeripheralManagerError.swift:39
        Row(
            identifier: "PeripheralManagerError.nack",
            message: "Nack",
            role: "errorMessage",
            taxonomy: "N8",
            expected: .other("Nack")
        ),
        // OmnipodKit/Bluetooth/PeripheralManagerError.swift:41
        Row(
            identifier: "PeripheralManagerError.unknownPodType",
            message: "Unknown Pod Type",
            role: "errorMessage",
            taxonomy: "N8",
            expected: .other("Unknown Pod Type")
        ),
        // OmnipodKit/Bluetooth/PodProtocolError.swift:25
        Row(
            identifier: "PodProtocolError.invalidLTKKey",
            message: "Invalid LTK Key: %1$@",
            role: "errorMessage",
            taxonomy: "N10",
            expected: .other("Invalid LTK Key: %1$@")
        ),
        // OmnipodKit/Bluetooth/PodProtocolError.swift:27
        Row(
            identifier: "PodProtocolError.pairingException",
            message: "Pairing Exception: %1$@",
            role: "errorMessage",
            taxonomy: "N10",
            expected: .other("Pairing Exception: %1$@")
        ),
        // OmnipodKit/Bluetooth/PodProtocolError.swift:29
        Row(
            identifier: "PodProtocolError.messageIOException",
            message: "Message IO Exception: %1$@",
            role: "errorMessage",
            taxonomy: "N8",
            expected: .other("Message IO Exception: %1$@")
        ),
        // OmnipodKit/Bluetooth/PodProtocolError.swift:31
        Row(
            identifier: "PodProtocolError.couldNotParseMessageException",
            message: "Could not parse message: %1$@",
            role: "errorMessage",
            taxonomy: "N8",
            expected: .other("Could not parse message: %1$@")
        ),
        // OmnipodKit/Bluetooth/PodProtocolError.swift:33-34
        Row(
            identifier: "PodProtocolError.incorrectPacketException",
            message: "Incorrect Packet Exception: %1$@ (location=%2$d)",
            role: "errorMessage",
            taxonomy: "N8",
            expected: .other("Incorrect Packet Exception: %1$@ (location=%2$d)")
        ),
        // OmnipodKit/Bluetooth/PodProtocolError.swift:35-36
        Row(
            identifier: "PodProtocolError.invalidCrc",
            message: "Payload crc32 %1$@ does not match computed crc32 %2$@",
            role: "errorMessage",
            taxonomy: "N8",
            expected: .other("Payload crc32 %1$@ does not match computed crc32 %2$@")
        ),
        // OmnipodKit/Bluetooth/BluetoothManager.swift:16,20-56
        Row(
            identifier: "BluetoothManagerError.bluetoothNotAvailable",
            message: "Bluetooth is powered off",
            role: "errorMessage",
            taxonomy: "N8",
            expected: .other("Bluetooth is powered off")
        ),
        // OmnipodKit/Bluetooth/BluetoothManager.swift:16,20-56
        Row(
            identifier: "BluetoothManagerError.bluetoothNotAvailable",
            message: "Bluetooth is resetting",
            role: "errorMessage",
            taxonomy: "N8",
            expected: .other("Bluetooth is resetting")
        ),
        // OmnipodKit/Bluetooth/BluetoothManager.swift:16,20-56
        Row(
            identifier: "BluetoothManagerError.bluetoothNotAvailable",
            message: "Bluetooth use is unauthorized",
            role: "errorMessage",
            taxonomy: "N8",
            expected: .other("Bluetooth use is unauthorized")
        ),
        // OmnipodKit/Bluetooth/BluetoothManager.swift:16,20-56
        Row(
            identifier: "BluetoothManagerError.bluetoothNotAvailable",
            message: "Bluetooth use unsupported on this device",
            role: "errorMessage",
            taxonomy: "N8",
            expected: .other("Bluetooth use unsupported on this device")
        ),
        // OmnipodKit/Bluetooth/BluetoothManager.swift:16,20-56
        Row(
            identifier: "BluetoothManagerError.bluetoothNotAvailable",
            message: "Bluetooth is unavailable for an unknown reason.",
            role: "errorMessage",
            taxonomy: "N8",
            expected: .other("Bluetooth is unavailable for an unknown reason.")
        ),
        // OmnipodKit/Bluetooth/BluetoothManager.swift:16,20-56
        Row(
            identifier: "BluetoothManagerError.bluetoothNotAvailable",
            message: "Bluetooth is unavailable: %1$@",
            role: "errorMessage",
            taxonomy: "N8",
            expected: .other("Bluetooth is unavailable: %1$@")
        ),
        // OmnipodKit/Bluetooth/BluetoothManager.swift:16,20-56
        Row(
            identifier: "BluetoothManagerError.bluetoothNotAvailable",
            message: "Turn bluetooth on",
            role: "errorMessage",
            taxonomy: "N8",
            expected: .other("Turn bluetooth on")
        ),
        // OmnipodKit/OmnipodCommon/MessageBlocks/ErrorResponse.swift:23-35
        Row(
            identifier: "ErrorResponseCode.badNonce",
            message: "Bad nonce",
            role: "errorMessage",
            taxonomy: "N9",
            expected: .other("Bad nonce")
        ),
        // OmnipodKit/OmnipodCommon/MessageBlocks/ErrorResponse.swift:23-35
        Row(
            identifier: "ErrorResponseCode.o5InvalidCommand",
            message: "Omnipod 5 invalid command",
            role: "errorMessage",
            taxonomy: "N9",
            expected: .other("Omnipod 5 invalid command")
        ),
        // OmnipodKit/OmnipodCommon/MessageBlocks/ErrorResponse.swift:23-35
        Row(
            identifier: "ErrorResponseCode.unknown",
            message: "Unknown error code %u (0x%02X)",
            role: "errorMessage",
            taxonomy: "N9",
            expected: .other("Unknown error code %u (0x%02X)")
        ),
        // OmnipodKit/Bluetooth/Session/Milenage.swift:14-16
        Row(
            identifier: "MilenageError.Error",
            message: "supplied string",
            role: "errorMessage",
            taxonomy: "N10",
            expected: .other("supplied string")
        ),
        // OmnipodKit/Services/O5AppAttestService.swift:201-208
        Row(
            identifier: "O5AuthError.offline",
            message: "The Internet connection appears to be offline.",
            role: "errorMessage",
            taxonomy: "N10",
            expected: .other("The Internet connection appears to be offline.")
        ),
        // OmnipodKit/Services/O5AppAttestService.swift:201-208
        Row(
            identifier: "O5AuthError.offline",
            message: "Please connect to Wi-Fi or Cellular Data and try again.",
            role: "errorMessage",
            taxonomy: "N10",
            expected: .other("Please connect to Wi-Fi or Cellular Data and try again.")
        ),
        // OmnipodKit/Services/O5AppAttestService.swift:134-136
        Row(
            identifier: "O5AuthError.tokenPromptDismissed",
            message: "Setup cancelled.",
            role: "errorMessage",
            taxonomy: "N10",
            expected: .other("Setup cancelled.")
        ),
        // OmnipodKit/Services/O5AppAttestService.swift:247-258
        Row(
            identifier: "O5AuthError.malformedStatus",
            message: "The key-management server is temporarily unavailable: received unexpected response.",
            role: "errorMessage",
            taxonomy: "N10",
            expected: .other("The key-management server is temporarily unavailable: received unexpected response.")
        ),
        // OmnipodKit/Services/O5AppAttestService.swift:247-258
        Row(
            identifier: "O5AuthError.malformedStatus",
            message: "Please try again later.",
            role: "errorMessage",
            taxonomy: "N10",
            expected: .other("Please try again later.")
        ),
        // OmnipodKit/Services/O5AppAttestService.swift:144
        Row(
            identifier: "O5AuthError.appAttestUnsupported",
            message: "App Attest is not supported on this device.",
            role: "errorMessage",
            taxonomy: "N10",
            expected: .other("App Attest is not supported on this device.")
        ),
        // OmnipodKit/Services/O5AppAttestService.swift:282
        Row(
            identifier: "O5AuthError.keyGeneration",
            message: "Failed to generate App Attest key: \\(error.localizedDescription)",
            role: "errorMessage",
            taxonomy: "N10",
            expected: .other("Failed to generate App Attest key: \\(error.localizedDescription)")
        ),
        // OmnipodKit/Services/O5AppAttestService.swift:290
        Row(
            identifier: "O5AuthError.attestation",
            message: "App Attest attestation failed: \\(error.localizedDescription)",
            role: "errorMessage",
            taxonomy: "N10",
            expected: .other("App Attest attestation failed: \\(error.localizedDescription)")
        ),
        // OmnipodKit/Services/O5AppAttestService.swift:298
        Row(
            identifier: "O5AuthError.bundleId",
            message: "Could not determine bundle identifier.",
            role: "errorMessage",
            taxonomy: "N10",
            expected: .other("Could not determine bundle identifier.")
        ),
        // OmnipodKit/Services/O5AppAttestService.swift:301
        Row(
            identifier: "O5AuthError.teamId",
            message: "Could not determine Team ID from provisioning profile.",
            role: "errorMessage",
            taxonomy: "N10",
            expected: .other("Could not determine Team ID from provisioning profile.")
        ),
        // OmnipodKit/Services/O5AppAttestService.swift:442
        Row(
            identifier: "O5AuthError.badResponse",
            message: "Invalid response from server.",
            role: "errorMessage",
            taxonomy: "N10",
            expected: .other("Invalid response from server.")
        ),
        // OmnipodKit/Services/O5AppAttestService.swift:457-465
        Row(
            identifier: "O5AuthError.httpError",
            message: "HTTP \\(statusCode)",
            role: "errorMessage",
            taxonomy: "N10",
            expected: .other("HTTP \\(statusCode)")
        ),
        // OmnipodKit/PumpManager/OmniPumpManager.swift:461-466
        Row(
            identifier: "lowRLBattery",
            message: "Low RileyLink Battery / \"%1$@\" has a low battery",
            role: "alertTitle",
            taxonomy: "F2",
            expected: .other("Low RileyLink Battery / \"%1$@\" has a low battery")
        ),
        // OmnipodKit/PumpManagerUI/Views/ManualTempBasalEntryView.swift:131-144
        Row(
            identifier: "ManualTempBasalEntryView.temporaryBasalFailed",
            message: "Temporary Basal Failed / Unable to set a temporary basal rate: %1$@",
            role: "alertTitle",
            taxonomy: "N9",
            expected: .other("Temporary Basal Failed / Unable to set a temporary basal rate: %1$@")
        ),
        // OmnipodKit/PumpManagerUI/Views/ManualTempBasalEntryView.swift:145-149
        Row(
            identifier: "ManualTempBasalEntryView.missingConfig",
            message: "Missing Config / This PumpManager has not been configured with a maximum basal rate because it was added before manual temp basal was a feature. Please set a new maximum basal rate.",
            role: "alertTitle",
            taxonomy: "N13",
            expected: .other(
                "Missing Config / This PumpManager has not been configured with a maximum basal rate because it was added before manual temp basal was a feature. Please set a new maximum basal rate."
            )
        ),
        // OmnipodKit/PumpManagerUI/Views/AttachPodView.swift:83-88
        Row(
            identifier: "AttachPodView.confirmAttachment",
            message: "Confirm Pod Attachment / Please confirm that the Pod is securely attached to your body.\n\nThe cannula can be inserted only once with each Pod. Tap \"Confirm\" when Pod is attached.",
            role: "alertTitle",
            taxonomy: "N12",
            expected: .other(
                "Confirm Pod Attachment / Please confirm that the Pod is securely attached to your body.\n\nThe cannula can be inserted only once with each Pod. Tap \"Confirm\" when Pod is attached."
            )
        ),
        // OmnipodKit/PumpManagerUI/Views/AttachPodView.swift:92-97
        Row(
            identifier: "AttachPodView.cancelSetup",
            message: "Are you sure you want to cancel Pod setup? / If you cancel Pod setup, the current Pod will be deactivated and will be unusable.",
            role: "alertTitle",
            taxonomy: "N12",
            expected: .other(
                "Are you sure you want to cancel Pod setup? / If you cancel Pod setup, the current Pod will be deactivated and will be unusable."
            )
        ),
        // OmnipodKit/PumpManagerUI/Views/DeactivatePodView.swift:86-91
        Row(
            identifier: "DeactivatePodView.removePod",
            message: "Remove Pod from Body / Your Pod may still be delivering Insulin.\nRemove it from your body, then tap \"Continue.\"",
            role: "alertTitle",
            taxonomy: "N12",
            expected: .other(
                "Remove Pod from Body / Your Pod may still be delivering Insulin.\nRemove it from your body, then tap \"Continue.\""
            )
        ),
        // OmnipodKit/PumpManagerUI/Views/ScheduledExpirationReminderEditView.swift:149-152
        Row(
            identifier: "ScheduledExpirationReminderEditView.updateFailed",
            message: "Failed to Update Expiration Reminder",
            role: "alertTitle",
            taxonomy: "N9",
            expected: .other("Failed to Update Expiration Reminder")
        ),
        // OmnipodKit/PumpManagerUI/Views/SilencePodSelectionView.swift:192-195
        Row(
            identifier: "SilencePodSelectionView.updateFailed",
            message: "Failed to update silence pod preference",
            role: "alertTitle",
            taxonomy: "N9",
            expected: .other("Failed to update silence pod preference")
        ),
        // OmnipodKit/PumpManagerUI/Views/BeepPreferenceSelectionView.swift:131-134
        Row(
            identifier: "BeepPreferenceSelectionView.updateFailed",
            message: "Failed to update confidence reminder preference",
            role: "alertTitle",
            taxonomy: "N9",
            expected: .other("Failed to update confidence reminder preference")
        ),
        // OmnipodKit/PumpManagerUI/Views/LowReservoirView.swift:195-198
        Row(
            identifier: "LowReservoirView.updateFailed",
            message: "Failed to Update Low Reservoir Value",
            role: "alertTitle",
            taxonomy: "N9",
            expected: .other("Failed to Update Low Reservoir Value")
        ),
        // OmnipodKit/PumpManagerUI/Views/ReadPodStatusView.swift:95-98
        Row(
            identifier: "ReadPodStatusView.readFailed",
            message: "Failed to read pod status",
            role: "alertTitle",
            taxonomy: "N9",
            expected: .other("Failed to read pod status")
        ),
        // OmnipodKit/PumpManagerUI/Views/PlayTestBeepsView.swift:80-83
        Row(
            identifier: "PlayTestBeepsView.failed",
            message: "Failed to play test beeps",
            role: "alertTitle",
            taxonomy: "N9",
            expected: .other("Failed to play test beeps")
        ),
        // OmnipodKit/PumpManagerUI/Views/ReadPodInfoView.swift:99-102
        Row(
            identifier: "ReadPodInfoView.readPulseLogFailed",
            message: "Failed to read pulse log",
            role: "alertTitle",
            taxonomy: "N9",
            expected: .other("Failed to read pulse log")
        ),
        // OmnipodKit/PumpManagerUI/Views/ReadPodInfoView.swift:99-102
        Row(
            identifier: "ReadPodInfoView.readPulseLogPlusFailed",
            message: "Failed to read pulse log plus",
            role: "alertTitle",
            taxonomy: "N9",
            expected: .other("Failed to read pulse log plus")
        ),
        // OmnipodKit/PumpManagerUI/Views/ReadPodInfoView.swift:99-102
        Row(
            identifier: "ReadPodInfoView.readActivationTimeFailed",
            message: "Failed to read activation time",
            role: "alertTitle",
            taxonomy: "N9",
            expected: .other("Failed to read activation time")
        ),
        // OmnipodKit/PumpManagerUI/Views/ReadPodInfoView.swift:99-102
        Row(
            identifier: "ReadPodInfoView.readTriggeredAlertsFailed",
            message: "Failed to read triggered alerts",
            role: "alertTitle",
            taxonomy: "N9",
            expected: .other("Failed to read triggered alerts")
        ),
        // OmnipodKit/PumpManagerUI/Views/CertificateDetailsViews.swift:95-108
        Row(
            identifier: "CertificateDetailsViews.importFailed",
            message: "Import Failed",
            role: "alertTitle",
            taxonomy: "N10",
            expected: .other("Import Failed")
        ),
        // OmnipodKit/PumpManagerUI/Views/DeliveryUncertaintyRecoveryView.swift:25,47
        Row(
            identifier: "DeliveryUncertaintyRecoveryView.unableToReachPod",
            message: "Unable to Reach Pod / %1$@ has been unable to communicate with the pod on your body since %2$@.\n\nDo not Discard Pod without scrolling to read this entire screen.\n\nCommunication was interrupted at a critical time. …",
            role: "alertTitle",
            taxonomy: "N3",
            expected: .commsTransient
        ),
        // OmnipodKit/PumpManagerUI/Views/UncertaintyRecoveredView.swift:21,34
        Row(
            identifier: "UncertaintyRecoveredView.commsRecovered",
            message: "Comms Recovered / %1$@ has recovered communication with the pod on your body.\n\nInsulin delivery records have been updated and should match what has actually been delivered. …",
            role: "alertTitle",
            taxonomy: "N14",
            expected: .commsTransient
        ),
        // OmnipodKit/PumpManager/OmniPumpManager.swift:821
        Row(
            identifier: "PumpStatusHighlight.commsIssue",
            message: "Comms Issue",
            role: "notificationTitle",
            taxonomy: "N3",
            expected: .commsTransient
        ),
        // OmnipodKit/PumpManager/OmniPumpManager.swift:829
        Row(
            identifier: "PumpStatusHighlight.finishSetup",
            message: "Finish Setup",
            role: "notificationTitle",
            taxonomy: "N14",
            expected: .other("Finish Setup")
        ),
        // OmnipodKit/PumpManager/OmniPumpManager.swift:834
        Row(
            identifier: "PumpStatusHighlight.finishDeactivation",
            message: "Finish Deactivation",
            role: "notificationTitle",
            taxonomy: "N14",
            expected: .other("Finish Deactivation")
        ),
        // OmnipodKit/PumpManager/OmniPumpManager.swift:839
        Row(
            identifier: "PumpStatusHighlight.noPod",
            message: "No Pod",
            role: "notificationTitle",
            taxonomy: "N14",
            expected: .other("No Pod")
        ),
        // OmnipodKit/PumpManager/OmniPumpManager.swift:843-848
        Row(
            identifier: "PumpStatusHighlight.podError",
            message: "Pod Error",
            role: "notificationTitle",
            taxonomy: "N1",
            expected: .other("Pod Error")
        ),
        // OmnipodKit/PumpManager/OmniPumpManager.swift:852
        Row(
            identifier: "PumpStatusHighlight.noInsulinFault",
            message: "No Insulin",
            role: "notificationTitle",
            taxonomy: "N4",
            expected: .other("No Insulin")
        ),
        // OmnipodKit/PumpManager/OmniPumpManager.swift:854
        Row(
            identifier: "PumpStatusHighlight.podExpiredFault",
            message: "Pod Expired",
            role: "notificationTitle",
            taxonomy: "N6",
            expected: .other("Pod Expired")
        ),
        // OmnipodKit/PumpManager/OmniPumpManager.swift:856
        Row(
            identifier: "PumpStatusHighlight.podOcclusion",
            message: "Pod Occlusion",
            role: "notificationTitle",
            taxonomy: "N1",
            expected: .occlusion
        ),
        // OmnipodKit/PumpManager/OmniPumpManager.swift:868
        Row(
            identifier: "PumpStatusHighlight.noInsulinReservoir",
            message: "No Insulin",
            role: "notificationTitle",
            taxonomy: "N4",
            expected: .other("No Insulin")
        ),
        // OmnipodKit/PumpManager/OmniPumpManager.swift:873
        Row(
            identifier: "PumpStatusHighlight.insulinSuspended",
            message: "Insulin Suspended",
            role: "notificationTitle",
            taxonomy: "N2",
            expected: .other("Insulin Suspended")
        ),
        // OmnipodKit/PumpManager/OmniPumpManager.swift:878
        Row(
            identifier: "PumpStatusHighlight.signalLoss",
            message: "Signal Loss",
            role: "notificationTitle",
            taxonomy: "N8",
            expected: .other("Signal Loss")
        ),
        // OmnipodKit/PumpManager/OmniPumpManager.swift:883
        Row(
            identifier: "PumpStatusHighlight.manualBasal",
            message: "Manual Basal",
            role: "notificationTitle",
            taxonomy: "N14",
            expected: .other("Manual Basal")
        )
    ]
    @Test(
        "each (identifier, message) classifies as pinned",
        arguments: rows
    ) func messageClassifiesAsPinned(_ row: Row) {
        let category = TrioAlertClassifier.categorize(error: StubError(description: row.message))
        #expect(category == row.expected)
    }

    // MARK: - Classifier coverage-gap ratchet

    //
    // Each key is "identifier — message" for a row whose pinned category is
    // .other(message) even though the message taxonomy assigns it a non-other
    // bucket. The per-entry comment names the bucket it SHOULD hit and why the
    // spaceless-substring check misses the spaced prose (with sourceRef). The test
    // recomputes this set from `rows` (expected == .other AND taxonomyBucket would
    // be non-other) and asserts equality, so improving the classifier shrinks the
    // recomputed set and FAILS the test — prompting an update here.
    static let classifierCoverageGaps: Set<String> = [
        // SHOULD hit .deviceExpired (deviceExpired); display prose contains spaces, so the spaceless substring check misses it. OmnipodKit/OmnipodCommon/PumpManagerAlert.swift:46,73
        "podExpireImminent — Pod Expired / Change Pod now. Insulin delivery will stop in 1 hour.",
        // SHOULD hit .deviceExpired (deviceExpired); display prose contains spaces, so the spaceless substring check misses it. OmnipodKit/OmnipodCommon/PumpManagerAlert.swift:42,69
        "userPodExpiration — Pod Expiration Reminder / Pod expires in %1$@.",
        // SHOULD hit .reservoirLow (reservoirLow); display prose contains spaces, so the spaceless substring check misses it. OmnipodKit/OmnipodCommon/PumpManagerAlert.swift:48,77
        "lowReservoir — Low Reservoir / %1$@ insulin or less remaining in Pod. Change Pod soon.",
        // SHOULD hit .deviceExpired (deviceExpired); display prose contains spaces, so the spaceless substring check misses it. OmnipodKit/OmnipodCommon/PumpManagerAlert.swift:44,71
        "podExpiring — Pod Expired / Change Pod now. Pod has been active for 72 hours.",
        // SHOULD hit .hardwareFault (hardwareFault); display prose contains spaces, so the spaceless substring check misses it. OmnipodKit/OmnipodCommon/PumpManagerAlert.swift:56,86
        "unexpectedAlert — Unexpected Alert / Unexpected Pod Alert #%1@!",
        // SHOULD hit .deviceExpired (deviceExpired); display prose contains spaces, so the spaceless substring check misses it. OmnipodKit/OmnipodCommon/AlertSlot.swift:108,147
        "PodAlert.shutdownImminent — Shutdown imminent",
        // SHOULD hit .deviceExpired (deviceExpired); display prose contains spaces, so the spaceless substring check misses it. OmnipodKit/OmnipodCommon/AlertSlot.swift:113,150
        "PodAlert.expirationReminder — Expiration reminder",
        // SHOULD hit .reservoirLow (reservoirLow); display prose contains spaces, so the spaceless substring check misses it. OmnipodKit/OmnipodCommon/AlertSlot.swift:116,153
        "PodAlert.lowReservoir — Low reservoir",
        // SHOULD hit .deviceExpired (deviceExpired); display prose contains spaces, so the spaceless substring check misses it. OmnipodKit/OmnipodCommon/AlertSlot.swift:134,166
        "PodAlert.expired — Pod expired",
        // SHOULD hit .reservoirEmpty (reservoirEmpty); display prose contains spaces, so the spaceless substring check misses it. OmnipodKit/OmnipodCommon/FaultEventCode.swift:646,659
        "reservoirEmpty — Empty Reservoir / Insulin delivery stopped. Change Pod now.",
        // SHOULD hit .deviceExpired (deviceExpired); display prose contains spaces, so the spaceless substring check misses it. OmnipodKit/OmnipodCommon/FaultEventCode.swift:650,659
        "exceededMaximumPodLife80Hrs — Pod Expired / Insulin delivery stopped. Change Pod now.",
        // SHOULD hit .hardwareFault (hardwareFault); display prose contains spaces, so the spaceless substring check misses it. OmnipodKit/OmnipodCommon/FaultEventCode.swift:619-640
        "FaultEventCode.localizedDescription — Empty reservoir",
        // SHOULD hit .hardwareFault (hardwareFault); display prose contains spaces, so the spaceless substring check misses it. OmnipodKit/OmnipodCommon/FaultEventCode.swift:619-640
        "FaultEventCode.localizedDescription — Pod expired",
        // SHOULD hit .commsTransient (commsTransient); display prose contains spaces, so the spaceless substring check misses it. OmnipodKit/PumpManager/PodCommsSession.swift:56
        "PodCommsError.noResponse — No response from pod",
        // SHOULD hit .commsTransient (commsTransient); display prose contains spaces, so the spaceless substring check misses it. OmnipodKit/PumpManager/PodCommsSession.swift:56
        "PodCommsError.noResponse — Make sure iPhone is nearby the active pod",
        // SHOULD hit .commsTransient (commsTransient); display prose contains spaces, so the spaceless substring check misses it. OmnipodKit/PumpManager/PodCommsSession.swift:56
        "PodCommsError.noResponseRL — No response from pod",
        // SHOULD hit .commsTransient (commsTransient); display prose contains spaces, so the spaceless substring check misses it. OmnipodKit/PumpManager/PodCommsSession.swift:56
        "PodCommsError.noResponseRL — Please try repositioning the pod or the RileyLink and try again",
        // SHOULD hit .commsTransient (commsTransient); display prose contains spaces, so the spaceless substring check misses it. OmnipodKit/PumpManager/PodCommsSession.swift:58
        "PodCommsError.emptyResponse — Empty response from pod",
        // SHOULD hit .commsTransient (commsTransient); display prose contains spaces, so the spaceless substring check misses it. OmnipodKit/PumpManager/PodCommsSession.swift:60
        "PodCommsError.podAckedInsteadOfReturningResponse — Pod sent ack instead of response",
        // SHOULD hit .commsTransient (commsTransient); display prose contains spaces, so the spaceless substring check misses it. OmnipodKit/PumpManager/PodCommsSession.swift:60
        "PodCommsError.podAckedInsteadOfReturningResponse — Try again",
        // SHOULD hit .commsTransient (commsTransient); display prose contains spaces, so the spaceless substring check misses it. OmnipodKit/PumpManager/PodCommsSession.swift:64
        "PodCommsError.unexpectedResponse — Unexpected response from pod",
        // SHOULD hit .commsTransient (commsTransient); display prose contains spaces, so the spaceless substring check misses it. OmnipodKit/PumpManager/PodCommsSession.swift:68
        "PodCommsError.invalidAddress — Invalid address 0x%x. Expected 0x%x",
        // SHOULD hit .commsTransient (commsTransient); display prose contains spaces, so the spaceless substring check misses it. OmnipodKit/PumpManager/PodCommsSession.swift:68
        "PodCommsError.invalidAddress — Crosstalk possible. Please move to a new location",
        // SHOULD hit .commsTransient (commsTransient); display prose contains spaces, so the spaceless substring check misses it. OmnipodKit/PumpManager/PodCommsSession.swift:70
        "PodCommsError.noRileyLinkAvailable — No RileyLink available",
        // SHOULD hit .commsTransient (commsTransient); display prose contains spaces, so the spaceless substring check misses it. OmnipodKit/PumpManager/PodCommsSession.swift:70
        "PodCommsError.noRileyLinkAvailable — Make sure your RileyLink is nearby and powered on",
        // SHOULD hit .commsTransient (commsTransient); display prose contains spaces, so the spaceless substring check misses it. OmnipodKit/PumpManager/PodCommsSession.swift:72
        "PodCommsError.podNotConnected — Pod not connected",
        // SHOULD hit .commsTransient (commsTransient); display prose contains spaces, so the spaceless substring check misses it. OmnipodKit/PumpManager/PodCommsSession.swift:72
        "PodCommsError.podNotConnected — Make sure your pod is nearby and try again",
        // SHOULD hit .deliveryUncertain (deliveryUncertain); display prose contains spaces, so the spaceless substring check misses it. OmnipodKit/PumpManager/PodCommsSession.swift:89
        "PodCommsError.unacknowledgedMessage — wrapped error's localizedDescription",
        // SHOULD hit .commsTransient (commsTransient); display prose contains spaces, so the spaceless substring check misses it. OmnipodKit/OmnipodCommon/Message.swift:26
        "MessageError.notEnoughData — Not enough data",
        // SHOULD hit .commsTransient (commsTransient); display prose contains spaces, so the spaceless substring check misses it. OmnipodKit/OmnipodCommon/Message.swift:28
        "MessageError.invalidCrc — Invalid CRC",
        // SHOULD hit .commsTransient (commsTransient); display prose contains spaces, so the spaceless substring check misses it. OmnipodKit/OmnipodCommon/Message.swift:30
        "MessageError.invalidSequence — Unexpected message sequence number",
        // SHOULD hit .commsTransient (commsTransient); display prose contains spaces, so the spaceless substring check misses it. OmnipodKit/OmnipodCommon/Message.swift:32
        "MessageError.invalidAddress — Invalid address: (%1$@)",
        // SHOULD hit .commsTransient (commsTransient); display prose contains spaces, so the spaceless substring check misses it. OmnipodKit/OmnipodCommon/Message.swift:34
        "MessageError.parsingError — Parsing Error: %1$@ in (%2$@)",
        // SHOULD hit .commsTransient (commsTransient); display prose contains spaces, so the spaceless substring check misses it. OmnipodKit/OmnipodCommon/Message.swift:36
        "MessageError.unknownValue — Unknown Value (%1$@) for type %2$@",
        // SHOULD hit .commsTransient (commsTransient); display prose contains spaces, so the spaceless substring check misses it. OmnipodKit/OmnipodCommon/Message.swift:38
        "MessageError.validationFailed — Validation failed: %1$@",
        // SHOULD hit .commsTransient (commsTransient); display prose contains spaces, so the spaceless substring check misses it. OmnipodKit/Bluetooth/PeripheralManagerError.swift:29
        "PeripheralManagerError.notReady — Peripheral Not Ready",
        // SHOULD hit .commsTransient (commsTransient); display prose contains spaces, so the spaceless substring check misses it. OmnipodKit/Bluetooth/PeripheralManagerError.swift:31
        "PeripheralManagerError.incorrectResponse — Incorrect Response",
        // SHOULD hit .commsTransient (commsTransient); display prose contains spaces, so the spaceless substring check misses it. OmnipodKit/Bluetooth/PeripheralManagerError.swift:35
        "PeripheralManagerError.emptyValue — Empty Value",
        // SHOULD hit .commsTransient (commsTransient); display prose contains spaces, so the spaceless substring check misses it. OmnipodKit/Bluetooth/PeripheralManagerError.swift:37
        "PeripheralManagerError.unknownCharacteristic — Unknown Characteristic",
        // SHOULD hit .commsTransient (commsTransient); display prose contains spaces, so the spaceless substring check misses it. OmnipodKit/Bluetooth/PeripheralManagerError.swift:39
        "PeripheralManagerError.nack — Nack",
        // SHOULD hit .commsTransient (commsTransient); display prose contains spaces, so the spaceless substring check misses it. OmnipodKit/Bluetooth/PeripheralManagerError.swift:41
        "PeripheralManagerError.unknownPodType — Unknown Pod Type",
        // SHOULD hit .commsTransient (commsTransient); display prose contains spaces, so the spaceless substring check misses it. OmnipodKit/Bluetooth/PodProtocolError.swift:29
        "PodProtocolError.messageIOException — Message IO Exception: %1$@",
        // SHOULD hit .commsTransient (commsTransient); display prose contains spaces, so the spaceless substring check misses it. OmnipodKit/Bluetooth/PodProtocolError.swift:31
        "PodProtocolError.couldNotParseMessageException — Could not parse message: %1$@",
        // SHOULD hit .commsTransient (commsTransient); display prose contains spaces, so the spaceless substring check misses it. OmnipodKit/Bluetooth/PodProtocolError.swift:33-34
        "PodProtocolError.incorrectPacketException — Incorrect Packet Exception: %1$@ (location=%2$d)",
        // SHOULD hit .commsTransient (commsTransient); display prose contains spaces, so the spaceless substring check misses it. OmnipodKit/Bluetooth/PodProtocolError.swift:35-36
        "PodProtocolError.invalidCrc — Payload crc32 %1$@ does not match computed crc32 %2$@",
        // SHOULD hit .commsTransient (commsTransient); display prose contains spaces, so the spaceless substring check misses it. OmnipodKit/Bluetooth/BluetoothManager.swift:16,20-56
        "BluetoothManagerError.bluetoothNotAvailable — Bluetooth is powered off",
        // SHOULD hit .commsTransient (commsTransient); display prose contains spaces, so the spaceless substring check misses it. OmnipodKit/Bluetooth/BluetoothManager.swift:16,20-56
        "BluetoothManagerError.bluetoothNotAvailable — Bluetooth is resetting",
        // SHOULD hit .commsTransient (commsTransient); display prose contains spaces, so the spaceless substring check misses it. OmnipodKit/Bluetooth/BluetoothManager.swift:16,20-56
        "BluetoothManagerError.bluetoothNotAvailable — Bluetooth use is unauthorized",
        // SHOULD hit .commsTransient (commsTransient); display prose contains spaces, so the spaceless substring check misses it. OmnipodKit/Bluetooth/BluetoothManager.swift:16,20-56
        "BluetoothManagerError.bluetoothNotAvailable — Bluetooth use unsupported on this device",
        // SHOULD hit .commsTransient (commsTransient); display prose contains spaces, so the spaceless substring check misses it. OmnipodKit/Bluetooth/BluetoothManager.swift:16,20-56
        "BluetoothManagerError.bluetoothNotAvailable — Bluetooth is unavailable for an unknown reason.",
        // SHOULD hit .commsTransient (commsTransient); display prose contains spaces, so the spaceless substring check misses it. OmnipodKit/Bluetooth/BluetoothManager.swift:16,20-56
        "BluetoothManagerError.bluetoothNotAvailable — Bluetooth is unavailable: %1$@",
        // SHOULD hit .commsTransient (commsTransient); display prose contains spaces, so the spaceless substring check misses it. OmnipodKit/Bluetooth/BluetoothManager.swift:16,20-56
        "BluetoothManagerError.bluetoothNotAvailable — Turn bluetooth on",
        // SHOULD hit .hardwareFault (hardwareFault); display prose contains spaces, so the spaceless substring check misses it. OmnipodKit/PumpManager/OmniPumpManager.swift:843-848
        "PumpStatusHighlight.podError — Pod Error",
        // SHOULD hit .reservoirEmpty (reservoirEmpty); display prose contains spaces, so the spaceless substring check misses it. OmnipodKit/PumpManager/OmniPumpManager.swift:852
        "PumpStatusHighlight.noInsulinFault — No Insulin",
        // SHOULD hit .deviceExpired (deviceExpired); display prose contains spaces, so the spaceless substring check misses it. OmnipodKit/PumpManager/OmniPumpManager.swift:854
        "PumpStatusHighlight.podExpiredFault — Pod Expired",
        // SHOULD hit .reservoirEmpty (reservoirEmpty); display prose contains spaces, so the spaceless substring check misses it. OmnipodKit/PumpManager/OmniPumpManager.swift:868
        "PumpStatusHighlight.noInsulinReservoir — No Insulin",
        // SHOULD hit .commsTransient (commsTransient); display prose contains spaces, so the spaceless substring check misses it. OmnipodKit/PumpManager/OmniPumpManager.swift:878
        "PumpStatusHighlight.signalLoss — Signal Loss"
    ] /// key -> whether the message taxonomy assigns a non-.other bucket.
    static let taxonomyBucketIsNonOther: [(String, Bool)] = [
        ("podExpireImminent — Pod Expired / Change Pod now. Insulin delivery will stop in 1 hour.", true),
        ("userPodExpiration — Pod Expiration Reminder / Pod expires in %1$@.", true),
        ("lowReservoir — Low Reservoir / %1$@ insulin or less remaining in Pod. Change Pod soon.", true),
        ("suspendInProgress — Suspend In Progress Reminder / Suspend In Progress Reminder", false),
        (
            "suspendEnded — Resume Insulin / The insulin suspension period has ended.\n\nYou can resume delivery from the banner on the home screen or from your pump settings screen. You will be reminded again in 15 minutes.",
            false
        ),
        ("suspendEnded — Suspension time is up. Open the app and resume.", false),
        ("podExpiring — Pod Expired / Change Pod now. Pod has been active for 72 hours.", true),
        ("finishSetupReminder — Pod Pairing Incomplete / Please finish pairing your pod.", false),
        ("unexpectedAlert — Unexpected Alert / Unexpected Pod Alert #%1@!", true),
        (
            "timeOffsetChangeDetected — Time Change Detected / The time on your pump is different from the current time. You can review the pump time and and sync to current time in settings.",
            false
        ),
        ("PodAlert.autoOff — Auto-off", false),
        ("PodAlert.shutdownImminent — Shutdown imminent", true),
        ("PodAlert.expirationReminder — Expiration reminder", true),
        ("PodAlert.lowReservoir — Low reservoir", true),
        ("PodAlert.podSuspendedReminder — Pod suspended reminder", false),
        ("PodAlert.suspendTimeExpired — Suspend time expired", false),
        ("PodAlert.waitingForPairingReminder — Waiting for pairing reminder", false),
        ("PodAlert.finishSetupReminder — Finish setup reminder", false),
        ("PodAlert.expired — Pod expired", true),
        ("reservoirEmpty — Empty Reservoir / Insulin delivery stopped. Change Pod now.", true),
        ("occlusion — Occlusion Detected / Insulin delivery stopped. Change Pod now.", true),
        ("exceededMaximumPodLife80Hrs — Pod Expired / Insulin delivery stopped. Change Pod now.", true),
        ("criticalPodFault — Critical Pod Fault %1$@ / Insulin delivery stopped. Change Pod now.", true),
        ("FaultEventCode.localizedDescription — No faults", true),
        ("FaultEventCode.localizedDescription — Empty reservoir", true),
        ("FaultEventCode.localizedDescription — Pod expired", true),
        ("FaultEventCode.localizedDescription — Occlusion detected", true),
        ("FaultEventCode.localizedDescription — Internal pod fault %1$@", true),
        ("FaultEventCode.localizedDescription — Unknown pod fault %1$@", true),
        ("PodCommsError.podFault — Pod Fault: %1$@", true),
        ("PodCommsError.noPodPaired — No pod paired", false),
        ("PodCommsError.noResponse — No response from pod", true),
        ("PodCommsError.noResponse — Make sure iPhone is nearby the active pod", true),
        ("PodCommsError.noResponseRL — No response from pod", true),
        ("PodCommsError.noResponseRL — Please try repositioning the pod or the RileyLink and try again", true),
        ("PodCommsError.emptyResponse — Empty response from pod", true),
        ("PodCommsError.podAckedInsteadOfReturningResponse — Pod sent ack instead of response", true),
        ("PodCommsError.podAckedInsteadOfReturningResponse — Try again", true),
        ("PodCommsError.unexpectedResponse — Unexpected response from pod", true),
        ("PodCommsError.invalidAddress — Invalid address 0x%x. Expected 0x%x", true),
        ("PodCommsError.invalidAddress — Crosstalk possible. Please move to a new location", true),
        ("PodCommsError.noRileyLinkAvailable — No RileyLink available", true),
        ("PodCommsError.noRileyLinkAvailable — Make sure your RileyLink is nearby and powered on", true),
        ("PodCommsError.podNotConnected — Pod not connected", true),
        ("PodCommsError.podNotConnected — Make sure your pod is nearby and try again", true),
        ("PodCommsError.unfinalizedBolus — Bolus in progress", false),
        ("PodCommsError.unfinalizedBolus — Wait for existing bolus to finish, or cancel bolus", false),
        ("PodCommsError.unfinalizedTempBasal — Temp basal in progress", false),
        ("PodCommsError.unfinalizedTempBasal — Wait for existing temp basal to finish, or suspend to cancel", false),
        ("PodCommsError.podSuspended — Pod is suspended", false),
        ("PodCommsError.podSuspended — Resume delivery", false),
        ("PodCommsError.unacknowledgedMessage — wrapped error's localizedDescription", true),
        ("PodCommsError.unacknowledgedCommandPending — Communication issue: Unacknowledged command pending.", true),
        ("PodCommsError.rejectedMessage — Command error %1$@: %2$@", false),
        ("PodCommsError.podChange — Unexpected pod change", false),
        ("PodCommsError.podChange — Please bring only original pod in range or deactivate original pod", false),
        ("PodCommsError.activationTimeExceeded — Activation time exceeded", false),
        ("PodCommsError.rssiTooLow — Poor signal strength", false),
        ("PodCommsError.rssiTooLow — Please reposition the RileyLink relative to the pod", false),
        ("PodCommsError.rssiTooHigh — Signal strength too high", false),
        ("PodCommsError.rssiTooHigh — Please reposition the RileyLink further from the pod", false),
        ("PodCommsError.diagnosticMessage — Received resynchronization SQN for the second time", false),
        ("PodCommsError.diagnosticMessage — Pod type not configured", false),
        ("PodCommsError.podIncompatible — Pod version %@ ... not supported", false),
        ("PodCommsError.noPodsFound — No pods found", false),
        ("PodCommsError.noPodsFound — Make sure your pod is filled and nearby", false),
        ("PodCommsError.tooManyPodsFound — Too many pods found", false),
        ("PodCommsError.tooManyPodsFound — Move to a new area away from any other pods and try again", false),
        ("PodCommsError.setupNotComplete — Pod setup is not complete", false),
        ("PodCommsError.noCertificateFound — No certificate found", false),
        ("PodCommsError.noCertificateFound — Retrieve an Omnipod 5 Pod Certificate to continue.", false),
        ("OmniPumpManagerError.noPodPaired — No pod paired", false),
        ("OmniPumpManagerError.noPodPaired — Please pair a new pod", false),
        ("OmniPumpManagerError.insulinTypeNotConfigured — Insulin type not configured", false),
        ("OmniPumpManagerError.notReadyForCannulaInsertion — Pod is not in a state ready for cannula insertion", false),
        ("OmniPumpManagerError.invalidSetting — Invalid Setting", false),
        ("OmniPumpManagerError.podTypeNotConfigured — Pod type not configured", false),
        ("OmniSettingsViewAlert.suspendError — Failed to Suspend Insulin Delivery", false),
        ("OmniSettingsViewAlert.resumeError — Failed to Resume Insulin Delivery", false),
        ("OmniSettingsViewAlert.syncTimeError — Failed to Set Pump Time", false),
        ("OmniSettingsViewAlert.cancelManualBasalError — Failed to Cancel Manual Basal", false),
        (
            "DeactivationError.OmniPumpManagerError — There was a problem communicating with the pod. If this problem persists, tap Discard Pod. You can then activate a new Pod.",
            false
        ),
        ("MessageError.notEnoughData — Not enough data", true),
        ("MessageError.invalidCrc — Invalid CRC", true),
        ("MessageError.invalidSequence — Unexpected message sequence number", true),
        ("MessageError.invalidAddress — Invalid address: (%1$@)", true),
        ("MessageError.parsingError — Parsing Error: %1$@ in (%2$@)", true),
        ("MessageError.unknownValue — Unknown Value (%1$@) for type %2$@", true),
        ("MessageError.validationFailed — Validation failed: %1$@", true),
        ("PeripheralManagerError.notReady — Peripheral Not Ready", true),
        ("PeripheralManagerError.incorrectResponse — Incorrect Response", true),
        ("PeripheralManagerError.timeout — Timeout", true),
        ("PeripheralManagerError.emptyValue — Empty Value", true),
        ("PeripheralManagerError.unknownCharacteristic — Unknown Characteristic", true),
        ("PeripheralManagerError.nack — Nack", true),
        ("PeripheralManagerError.unknownPodType — Unknown Pod Type", true),
        ("PodProtocolError.invalidLTKKey — Invalid LTK Key: %1$@", false),
        ("PodProtocolError.pairingException — Pairing Exception: %1$@", false),
        ("PodProtocolError.messageIOException — Message IO Exception: %1$@", true),
        ("PodProtocolError.couldNotParseMessageException — Could not parse message: %1$@", true),
        ("PodProtocolError.incorrectPacketException — Incorrect Packet Exception: %1$@ (location=%2$d)", true),
        ("PodProtocolError.invalidCrc — Payload crc32 %1$@ does not match computed crc32 %2$@", true),
        ("BluetoothManagerError.bluetoothNotAvailable — Bluetooth is powered off", true),
        ("BluetoothManagerError.bluetoothNotAvailable — Bluetooth is resetting", true),
        ("BluetoothManagerError.bluetoothNotAvailable — Bluetooth use is unauthorized", true),
        ("BluetoothManagerError.bluetoothNotAvailable — Bluetooth use unsupported on this device", true),
        ("BluetoothManagerError.bluetoothNotAvailable — Bluetooth is unavailable for an unknown reason.", true),
        ("BluetoothManagerError.bluetoothNotAvailable — Bluetooth is unavailable: %1$@", true),
        ("BluetoothManagerError.bluetoothNotAvailable — Turn bluetooth on", true),
        ("ErrorResponseCode.badNonce — Bad nonce", false),
        ("ErrorResponseCode.o5InvalidCommand — Omnipod 5 invalid command", false),
        ("ErrorResponseCode.unknown — Unknown error code %u (0x%02X)", false),
        ("MilenageError.Error — supplied string", false),
        ("O5AuthError.offline — The Internet connection appears to be offline.", false),
        ("O5AuthError.offline — Please connect to Wi-Fi or Cellular Data and try again.", false),
        ("O5AuthError.tokenPromptDismissed — Setup cancelled.", false),
        (
            "O5AuthError.malformedStatus — The key-management server is temporarily unavailable: received unexpected response.",
            false
        ),
        ("O5AuthError.malformedStatus — Please try again later.", false),
        ("O5AuthError.appAttestUnsupported — App Attest is not supported on this device.", false),
        ("O5AuthError.keyGeneration — Failed to generate App Attest key: \\(error.localizedDescription)", false),
        ("O5AuthError.attestation — App Attest attestation failed: \\(error.localizedDescription)", false),
        ("O5AuthError.bundleId — Could not determine bundle identifier.", false),
        ("O5AuthError.teamId — Could not determine Team ID from provisioning profile.", false),
        ("O5AuthError.badResponse — Invalid response from server.", false),
        ("O5AuthError.httpError — HTTP \\(statusCode)", false),
        ("lowRLBattery — Low RileyLink Battery / \"%1$@\" has a low battery", false),
        (
            "ManualTempBasalEntryView.temporaryBasalFailed — Temporary Basal Failed / Unable to set a temporary basal rate: %1$@",
            false
        ),
        (
            "ManualTempBasalEntryView.missingConfig — Missing Config / This PumpManager has not been configured with a maximum basal rate because it was added before manual temp basal was a feature. Please set a new maximum basal rate.",
            false
        ),
        (
            "AttachPodView.confirmAttachment — Confirm Pod Attachment / Please confirm that the Pod is securely attached to your body.\n\nThe cannula can be inserted only once with each Pod. Tap \"Confirm\" when Pod is attached.",
            false
        ),
        (
            "AttachPodView.cancelSetup — Are you sure you want to cancel Pod setup? / If you cancel Pod setup, the current Pod will be deactivated and will be unusable.",
            false
        ),
        (
            "DeactivatePodView.removePod — Remove Pod from Body / Your Pod may still be delivering Insulin.\nRemove it from your body, then tap \"Continue.\"",
            false
        ),
        ("ScheduledExpirationReminderEditView.updateFailed — Failed to Update Expiration Reminder", false),
        ("SilencePodSelectionView.updateFailed — Failed to update silence pod preference", false),
        ("BeepPreferenceSelectionView.updateFailed — Failed to update confidence reminder preference", false),
        ("LowReservoirView.updateFailed — Failed to Update Low Reservoir Value", false),
        ("ReadPodStatusView.readFailed — Failed to read pod status", false),
        ("PlayTestBeepsView.failed — Failed to play test beeps", false),
        ("ReadPodInfoView.readPulseLogFailed — Failed to read pulse log", false),
        ("ReadPodInfoView.readPulseLogPlusFailed — Failed to read pulse log plus", false),
        ("ReadPodInfoView.readActivationTimeFailed — Failed to read activation time", false),
        ("ReadPodInfoView.readTriggeredAlertsFailed — Failed to read triggered alerts", false),
        ("CertificateDetailsViews.importFailed — Import Failed", false),
        (
            "DeliveryUncertaintyRecoveryView.unableToReachPod — Unable to Reach Pod / %1$@ has been unable to communicate with the pod on your body since %2$@.\n\nDo not Discard Pod without scrolling to read this entire screen.\n\nCommunication was interrupted at a critical time. …",
            true
        ),
        (
            "UncertaintyRecoveredView.commsRecovered — Comms Recovered / %1$@ has recovered communication with the pod on your body.\n\nInsulin delivery records have been updated and should match what has actually been delivered. …",
            false
        ),
        ("PumpStatusHighlight.commsIssue — Comms Issue", true),
        ("PumpStatusHighlight.finishSetup — Finish Setup", false),
        ("PumpStatusHighlight.finishDeactivation — Finish Deactivation", false),
        ("PumpStatusHighlight.noPod — No Pod", false),
        ("PumpStatusHighlight.podError — Pod Error", true),
        ("PumpStatusHighlight.noInsulinFault — No Insulin", true),
        ("PumpStatusHighlight.podExpiredFault — Pod Expired", true),
        ("PumpStatusHighlight.podOcclusion — Pod Occlusion", true),
        ("PumpStatusHighlight.noInsulinReservoir — No Insulin", true),
        ("PumpStatusHighlight.insulinSuspended — Insulin Suspended", false),
        ("PumpStatusHighlight.signalLoss — Signal Loss", true),
        ("PumpStatusHighlight.manualBasal — Manual Basal", false)
    ]
    /// Identifier — message keys whose message taxonomy assigns a non-other bucket.
    /// Mirrors the per-row taxonomyBucket from the audit; used to recompute gaps.
    /// (key, hasNonOtherTaxonomyBucket).
    static let nonOtherTaxonomyKeys: Set<String> = {
        var s: Set<String> = []
        for (key, nonOther) in taxonomyBucketIsNonOther where nonOther {
            s.insert(key)
        }
        return s
    }()

    @Test("classifier coverage gaps are exactly as pinned") func coverageGapsAreExactlyAsPinned() {
        var recomputed: Set<String> = []
        for row in Self.rows {
            let key = "\(row.identifier) — \(row.message)"
            let landedInOther: Bool = {
                if case .other = row.expected { return true }
                return false
            }()
            if landedInOther, Self.nonOtherTaxonomyKeys.contains(key) {
                recomputed.insert(key)
            }
        }
        #expect(recomputed == Self.classifierCoverageGaps)
    }
}
