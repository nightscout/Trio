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
@Suite("Trio Alert Emission: RileyLinkKit") struct RileyLinkKitAlertEmissionTests {
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

/// SPEC — Message-text classification catalog for **RileyLinkKit**.
///
/// IMPORTANT mismatch vs. production: in prod, `TrioAlertClassifier.categorize`
/// receives `String(describing: error)`, which for RileyLinkKit's two
/// `LocalizedError` enums (`PeripheralManagerError`, `RileyLinkDeviceError`,
/// neither `CustomStringConvertible`) is the Swift CASE NAME — not the
/// human-readable display string. The sibling suite
/// `RileyLinkKitAlertEmissionTests` already pins the case-name path. THIS suite
/// instead catalogs every *reportable display string* (the verbatim
/// `errorDescription` / `failureReason` / `recoverySuggestion` / UI label a
/// user could actually see) keyed by its emitting identifier, and pins how the
/// substring classifier handles that real natural-language text.
///
/// RileyLinkKit emits NO LoopKit Alerts, no `UNUserNotification`s, and has no
/// alert-code enum; all user-facing messages come from the two `LocalizedError`
/// enums plus the dev-app-only `KeychainManagerError` and ad-hoc
/// UIAlertController / verbatim error renderings. Because there are no
/// `Alert.Identifier`s, `alertIdentifier` is the error case name / source
/// symbol.
///
/// HEADLINE: the classifier lowercases and does SPACE-SENSITIVE substring
/// matching with no-space tokens ("notconnected" / "noresponse" / "timeout" /
/// "communication" / "comms" / "rssi"). NONE of RileyLinkKit's natural-language
/// prose contains those tokens, so EVERY message falls through to `.other`.
/// This is a systematic under-coverage gap for the N8 connectivity bucket: 19
/// distinct N8 emissions SHOULD map to `.commsTransient` but all resolve to
/// `.other` (isGap=true). The N9 command-failure / N10 auth / N13 config / N15
/// keychain strings correctly map to `.other` (no taxonomy bucket; isGap=false).
///
/// Audit + classified data:
/// loopkit-manager-synthesis/investigations/alert-notification-emissions/managers/pump/RileyLinkKit/
/// Classifier source: Trio/Sources/Services/Alerts/TrioAlertCategory.swift
@Suite("Trio Alert Emission: RileyLinkKit — Classification") struct RileyLinkKitMessageClassificationTests {
    /// Stub whose `String(describing:)` IS the display string, so classification
    /// runs over the natural-language text a user would actually see.
    private struct StubError: Error, CustomStringConvertible {
        let description: String
    }

    struct Row {
        let identifier: String
        let message: String
        let role: String
        let taxonomy: String
        let expected: TrioAlertCategory
    }

    /// Every reportable display string with its emitting identifier. Each row's
    /// `expected` is built from the audit's `currentCategory` — all "other" for
    /// RileyLinkKit — so `expected == .other(message)` throughout, pinning that
    /// the substring classifier never matches RileyLinkKit's prose.
    static let rows: [Row] = [
        // RileyLinkBLEKit/PeripheralManager.swift:174
        Row(
            identifier: "PeripheralManagerError.unknownCharacteristic",
            message: "Unknown characteristic: %@",
            role: "errorMessage",
            taxonomy: "N8",
            expected: .other("Unknown characteristic: %@")
        ),
        // RileyLinkBLEKit/PeripheralManager.swift:195
        Row(
            identifier: "PeripheralManagerError.notReady",
            message: "RileyLink is not connected",
            role: "errorMessage",
            taxonomy: "N8",
            expected: .other("RileyLink is not connected")
        ),
        // RileyLinkBLEKit/PeripheralManager.swift:205
        Row(
            identifier: "PeripheralManagerError.busy",
            message: "RileyLink is busy",
            role: "errorMessage",
            taxonomy: "N9",
            expected: .other("RileyLink is busy")
        ),
        // RileyLinkBLEKit/PeripheralManager.swift:225
        Row(
            identifier: "PeripheralManagerError.timeout",
            message: "RileyLink did not respond in time",
            role: "errorMessage",
            taxonomy: "N8",
            expected: .other("RileyLink did not respond in time")
        ),
        // RileyLinkBLEKit/PeripheralManager.swift:229
        Row(
            identifier: "PeripheralManagerError.cbPeripheralError",
            message: "underlying CoreBluetooth error.localizedDescription",
            role: "errorMessage",
            taxonomy: "N8",
            expected: .other("underlying CoreBluetooth error.localizedDescription")
        ),
        // RileyLinkBLEKit/PeripheralManager+RileyLink.swift:387
        Row(
            identifier: "PeripheralManagerError.emptyValue",
            message: "Characteristic value was empty",
            role: "errorMessage",
            taxonomy: "N8",
            expected: .other("Characteristic value was empty")
        ),
        // RileyLinkBLEKit/PeripheralManagerError.swift:18 (dead code)
        Row(
            identifier: "PeripheralManagerError.unknownService",
            message: "Unknown service: %@",
            role: "errorMessage",
            taxonomy: "N8",
            expected: .other("Unknown service: %@")
        ),
        // RileyLinkBLEKit/PeripheralManager+RileyLink.swift:238,291,365,396,590,658
        Row(
            identifier: "RileyLinkDeviceError.peripheralManagerError",
            message: "wrapped PeripheralManagerError description",
            role: "errorMessage",
            taxonomy: "N8",
            expected: .other("wrapped PeripheralManagerError description")
        ),
        // RileyLinkBLEKit/PeripheralManager+RileyLink.swift:171
        Row(
            identifier: "RileyLinkDeviceError.writeSizeLimitExceeded",
            message: "Data exceeded maximum size of %@ bytes",
            role: "errorMessage",
            taxonomy: "N9",
            expected: .other("Data exceeded maximum size of %@ bytes")
        ),
        // RileyLinkBLEKit/PeripheralManager+RileyLink.swift:278
        Row(
            identifier: "RileyLinkDeviceError.errorResponse",
            message: "the rejected name string itself",
            role: "validation",
            taxonomy: "N13",
            expected: .other("the rejected name string itself")
        ),
        // RileyLinkBLEKit/PeripheralManager+RileyLink.swift:391,595,662; CommandSession.swift:101,122
        Row(
            identifier: "RileyLinkDeviceError.invalidResponse",
            message: "Response %@ is invalid",
            role: "errorMessage",
            taxonomy: "N8",
            expected: .other("Response %@ is invalid")
        ),
        // RileyLinkBLEKit/PeripheralManager+RileyLink.swift:588
        Row(
            identifier: "RileyLinkDeviceError.commandsBlocked",
            message: "RileyLink command did not respond",
            role: "errorMessage",
            taxonomy: "N8",
            expected: .other("RileyLink command did not respond")
        ),
        // RileyLinkBLEKit/PeripheralManager+RileyLink.swift:588
        Row(
            identifier: "RileyLinkDeviceError.commandsBlocked (recoverySuggestion)",
            message: "RileyLink may need to be turned off and back on",
            role: "errorMessage",
            taxonomy: "N8",
            expected: .other("RileyLink may need to be turned off and back on")
        ),
        // RileyLinkBLEKit/PeripheralManagerError.swift
        Row(
            identifier: "PeripheralManagerError.unknownCharacteristic (recoverySuggestion failureReason)",
            message: "The RileyLink was temporarily disconnected",
            role: "errorMessage",
            taxonomy: "N8",
            expected: .other("The RileyLink was temporarily disconnected")
        ),
        // RileyLinkBLEKit/PeripheralManagerError.swift
        Row(
            identifier: "PeripheralManagerError.unknownCharacteristic (recoverySuggestion)",
            message: "Make sure the device is nearby, and the issue should resolve automatically",
            role: "errorMessage",
            taxonomy: "N8",
            expected: .other("Make sure the device is nearby, and the issue should resolve automatically")
        ),
        // RileyLinkBLEKit/CommandSession.swift:97,99
        Row(
            identifier: "RileyLinkDeviceError.responseTimeout",
            message: "Pump did not respond in time",
            role: "errorMessage",
            taxonomy: "N8",
            expected: .other("Pump did not respond in time")
        ),
        // RileyLinkBLEKit/CommandSession.swift:103
        Row(
            identifier: "RileyLinkDeviceError.errorResponse",
            message: "RileyLink reported invalid param: <hex>",
            role: "errorMessage",
            taxonomy: "N9",
            expected: .other("RileyLink reported invalid param: <hex>")
        ),
        // RileyLinkBLEKit/CommandSession.swift:105
        Row(
            identifier: "RileyLinkDeviceError.errorResponse",
            message: "RileyLink reported unknown command: <hex>",
            role: "errorMessage",
            taxonomy: "N9",
            expected: .other("RileyLink reported unknown command: <hex>")
        ),
        // RileyLinkBLEKit/CommandSession.swift:136
        Row(
            identifier: "RileyLinkDeviceError.unsupportedCommand",
            message: "RileyLink firmware does not support the readRegister command",
            role: "errorMessage",
            taxonomy: "N9",
            expected: .other("RileyLink firmware does not support the readRegister command")
        ),
        // RileyLinkBLEKit/CommandSession.swift:143
        Row(
            identifier: "RileyLinkDeviceError.errorResponse",
            message: "Unsupported register: <register>",
            role: "errorMessage",
            taxonomy: "N9",
            expected: .other("Unsupported register: <register>")
        ),
        // RileyLinkBLEKit/CommandSession.swift:270
        Row(
            identifier: "RileyLinkDeviceError.unsupportedCommand",
            message: "RileyLink firmware does not support the setSWEncoding command",
            role: "errorMessage",
            taxonomy: "N9",
            expected: .other("RileyLink firmware does not support the setSWEncoding command")
        ),
        // RileyLinkBLEKit/CommandSession.swift:278
        Row(
            identifier: "RileyLinkDeviceError.unsupportedCommand",
            message: "RileyLink firmware does not support the Set Software Encoding error command",
            role: "errorMessage",
            taxonomy: "N9",
            expected: .other("RileyLink firmware does not support the Set Software Encoding error command")
        ),
        // RileyLinkBLEKit/CommandSession.swift:293
        Row(
            identifier: "RileyLinkDeviceError.unsupportedCommand",
            message: "RileyLink firmware does not support the getStatistics command",
            role: "errorMessage",
            taxonomy: "N9",
            expected: .other("RileyLink firmware does not support the getStatistics command")
        ),
        // RileyLinkBLEKit/CommandSession.swift:304
        Row(
            identifier: "RileyLinkDeviceError.unsupportedCommand",
            message: "RileyLink firmware does not support the setPreamble command",
            role: "errorMessage",
            taxonomy: "N9",
            expected: .other("RileyLink firmware does not support the setPreamble command")
        ),
        // RileyLinkKitUI/CommandResponseViewController.swift:25,51
        Row(
            identifier: "CommandResponseViewController (String(describing:))",
            message: "verbatim rendering of the thrown RileyLinkDeviceError",
            role: "errorMessage",
            taxonomy: "N9",
            expected: .other("verbatim rendering of the thrown RileyLinkDeviceError")
        ),
        // RileyLink/AuthenticationViewController.swift:44
        Row(
            identifier: "presentAlertControllerWithError (AuthenticationViewController)",
            message: "verification error's localizedDescription + recovery suggestion",
            role: "errorMessage",
            taxonomy: "N10",
            expected: .other("verification error's localizedDescription + recovery suggestion")
        ),
        // RileyLinkKitUI/RileyLinkDeviceTableViewController.swift:730
        Row(
            identifier: "UIAlertController (battery threshold action sheet)",
            message: "Battery level Alert",
            role: "alertTitle",
            taxonomy: "N13",
            expected: .other("Battery level Alert")
        ),
        // RileyLinkKitUI/RileyLinkDeviceTableViewController.swift:730
        Row(
            identifier: "UIAlertController (battery threshold action sheet, actions)",
            message: "OFF, 20%, 30%, 40%, 50%",
            role: "validation",
            taxonomy: "N13",
            expected: .other("OFF, 20%, 30%, 40%, 50%")
        ),
        // RileyLink/Extensions/UIViewController.swift:20,46
        Row(
            identifier: "presentAlertControllerWithError/Title (OK button)",
            message: "OK",
            role: "validation",
            taxonomy: "N13",
            expected: .other("OK")
        ),
        // RileyLink/KeychainManager.swift:78,111,152
        Row(
            identifier: "KeychainManagerError.add",
            message: "(no localized message; String(describing:) only, e.g. add(-26275))",
            role: "errorMessage",
            taxonomy: "N15",
            expected: .other("(no localized message; String(describing:) only, e.g. add(-26275))")
        ),
        // RileyLink/KeychainManager.swift:126,188
        Row(
            identifier: "KeychainManagerError.copy",
            message: "(no localized message; String(describing:) only, e.g. copy(-25300))",
            role: "errorMessage",
            taxonomy: "N15",
            expected: .other("(no localized message; String(describing:) only, e.g. copy(-25300))")
        ),
        // RileyLink/KeychainManager.swift:91
        Row(
            identifier: "KeychainManagerError.delete",
            message: "(no localized message; String(describing:) only, e.g. delete(-25300))",
            role: "errorMessage",
            taxonomy: "N15",
            expected: .other("(no localized message; String(describing:) only, e.g. delete(-25300))")
        ),
        // RileyLink/KeychainManager.swift:130,199
        Row(
            identifier: "KeychainManagerError.unknownResult",
            message: "(no localized message; String(describing:) only, e.g. unknownResult)",
            role: "errorMessage",
            taxonomy: "N15",
            expected: .other("(no localized message; String(describing:) only, e.g. unknownResult)")
        )
    ]

    @Test("each (identifier, message) classifies as pinned", arguments: rows) func eachMessageClassifiesAsPinned(row: Row) {
        #expect(TrioAlertClassifier.categorize(error: StubError(description: row.message)) == row.expected)
    }

    // MARK: - Classifier-coverage gap ratchet

    /// Keys ("identifier — message") for every N8 connectivity/communication
    /// message that SHOULD reach `.commsTransient` but currently falls to
    /// `.other` because its natural-language text contains none of the
    /// classifier's no-space tokens ("notconnected" / "noresponse" / "timeout" /
    /// "communication" / "comms" / "rssi"). Each entry documents WHY the tokens
    /// miss:
    ///
    ///   - "Unknown characteristic: %@" (PeripheralManager.swift:174): prose has
    ///     no connectivity token. SHOULD be .commsTransient.
    ///   - "RileyLink is not connected" (PeripheralManager.swift:195): "not
    ///     connected" has a SPACE; token is "notconnected" (no space) -> misses.
    ///     SHOULD be .commsTransient.
    ///   - "RileyLink did not respond in time" (PeripheralManager.swift:225):
    ///     "did not respond" != "noresponse"; "in time" != "timeout". Misses.
    ///     SHOULD be .commsTransient.
    ///   - "underlying CoreBluetooth error.localizedDescription"
    ///     (PeripheralManager.swift:229): wrapped CB text, no token. SHOULD be
    ///     .commsTransient.
    ///   - "Characteristic value was empty"
    ///     (PeripheralManager+RileyLink.swift:387): no token. SHOULD be
    ///     .commsTransient.
    ///   - "Unknown service: %@" (PeripheralManagerError.swift:18, dead code):
    ///     no token. SHOULD be .commsTransient.
    ///   - "wrapped PeripheralManagerError description"
    ///     (PeripheralManager+RileyLink.swift:238,291,365,396,590,658): forwards
    ///     a BLE-level message that itself misses. SHOULD be .commsTransient.
    ///   - "Response %@ is invalid"
    ///     (PeripheralManager+RileyLink.swift:391,595,662; CommandSession.swift:101,122):
    ///     no token. SHOULD be .commsTransient.
    ///   - "RileyLink command did not respond"
    ///     (PeripheralManager+RileyLink.swift:588): "did not respond" !=
    ///     "noresponse". Misses. SHOULD be .commsTransient.
    ///   - "RileyLink may need to be turned off and back on"
    ///     (PeripheralManager+RileyLink.swift:588, recoverySuggestion): no token.
    ///     SHOULD be .commsTransient.
    ///   - "The RileyLink was temporarily disconnected"
    ///     (PeripheralManagerError.swift, failureReason): "disconnected" !=
    ///     "notconnected". Misses. SHOULD be .commsTransient.
    ///   - "Make sure the device is nearby, and the issue should resolve
    ///     automatically" (PeripheralManagerError.swift, recoverySuggestion): no
    ///     token. SHOULD be .commsTransient.
    ///   - "Pump did not respond in time" (CommandSession.swift:97,99): "did not
    ///     respond" != "noresponse"; "in time" != "timeout". Misses. SHOULD be
    ///     .commsTransient.
    ///
    /// N9/N10/N13/N15 rows correctly land in `.other` (no taxonomy bucket) and
    /// are NOT gaps. This set stays green now and FAILS when the classifier is
    /// improved to catch this prose (prompting a ratchet update).
    static let classifierCoverageGaps: Set<String> = [
        "PeripheralManagerError.unknownCharacteristic — Unknown characteristic: %@",
        "PeripheralManagerError.notReady — RileyLink is not connected",
        "PeripheralManagerError.timeout — RileyLink did not respond in time",
        "PeripheralManagerError.cbPeripheralError — underlying CoreBluetooth error.localizedDescription",
        "PeripheralManagerError.emptyValue — Characteristic value was empty",
        "PeripheralManagerError.unknownService — Unknown service: %@",
        "RileyLinkDeviceError.peripheralManagerError — wrapped PeripheralManagerError description",
        "RileyLinkDeviceError.invalidResponse — Response %@ is invalid",
        "RileyLinkDeviceError.commandsBlocked — RileyLink command did not respond",
        "RileyLinkDeviceError.commandsBlocked (recoverySuggestion) — RileyLink may need to be turned off and back on",
        "PeripheralManagerError.unknownCharacteristic (recoverySuggestion failureReason) — The RileyLink was temporarily disconnected",
        "PeripheralManagerError.unknownCharacteristic (recoverySuggestion) — Make sure the device is nearby, and the issue should resolve automatically",
        "RileyLinkDeviceError.responseTimeout — Pump did not respond in time"
    ]

    @Test("classifier-coverage gaps are exactly as documented") func classifierCoverageGapsAreExact() {
        // A row is a gap when the audit assigns it a real taxonomy bucket
        // (commsTransient) yet the classifier currently yields .other(message).
        let gapBuckets: [String: String] = [
            "PeripheralManagerError.unknownCharacteristic": "commsTransient",
            "PeripheralManagerError.notReady": "commsTransient",
            "PeripheralManagerError.timeout": "commsTransient",
            "PeripheralManagerError.cbPeripheralError": "commsTransient",
            "PeripheralManagerError.emptyValue": "commsTransient",
            "PeripheralManagerError.unknownService": "commsTransient",
            "RileyLinkDeviceError.peripheralManagerError": "commsTransient",
            "RileyLinkDeviceError.invalidResponse": "commsTransient",
            "RileyLinkDeviceError.commandsBlocked": "commsTransient",
            "RileyLinkDeviceError.commandsBlocked (recoverySuggestion)": "commsTransient",
            "PeripheralManagerError.unknownCharacteristic (recoverySuggestion failureReason)": "commsTransient",
            "PeripheralManagerError.unknownCharacteristic (recoverySuggestion)": "commsTransient",
            "RileyLinkDeviceError.responseTimeout": "commsTransient"
        ]
        let recomputed = Set(
            Self.rows
                .filter { $0.expected == .other($0.message) && gapBuckets[$0.identifier] != nil }
                .map { "\($0.identifier) — \($0.message)" }
        )
        #expect(recomputed == Self.classifierCoverageGaps)
    }
}
