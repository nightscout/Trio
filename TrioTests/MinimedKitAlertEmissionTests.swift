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
@Suite("Trio Alert Emission: MinimedKit") struct MinimedKitAlertEmissionTests {
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

// MARK: - Message classification

/// SPEC — This suite catalogs every user-reportable string MinimedKit can
/// surface (PumpAlarmType titles, PumpErrorCode / PumpOpsError /
/// PumpCommandError / MinimedPumpManagerError descriptions, SetBolusError,
/// the four LoopKit `issueAlert` constructions, PumpStatusHighlight banners,
/// settings-view alerts, the time-change action sheet, and history/glucose
/// page parse errors) and pins how `TrioAlertClassifier.categorize(error:)`
/// routes each one.
///
/// IMPORTANT mismatch this pins: in production the classifier is fed
/// `String(describing: error)` — i.e. the Swift *case name* of an enum error,
/// not the localized display string a user sees. Its checks then match
/// concatenated, lowercased tokens (`"reservoirempty"`, `"noresponse"`,
/// `"comms"`, …) that only ever appear in case-name form. We instead feed each
/// row's real DISPLAY string through a `StubError` whose `String(describing:)`
/// IS that exact prose. Because natural-language prose has spaces and never
/// contains those concatenated tokens, almost every real MinimedKit message
/// falls through to `.other`. The only display strings that DO hit a bucket
/// are ones whose substrings coincidentally coincide with a classifier token:
/// "Comms with another pump detected" -> `.commsTransient` (contains "comms")
/// and "Bolus may have failed: …" -> `.deliveryUncertain`.
///
/// This is the audit over the managers / pump / MinimedKit sources
/// (`MinimedKit/...`). Each row pins CURRENT behavior (must be green) and the
/// gap ratchet below fails when the classifier is improved to map the
/// taxonomy-intended messages.
@Suite("Trio Alert Emission: MinimedKit — Classification") struct MinimedKitMessageClassificationTests {
    private struct StubError: Error, CustomStringConvertible { let description: String }

    struct Row {
        let identifier: String
        let message: String
        let role: String
        let taxonomy: String
        let expected: TrioAlertCategory
    }

    static let rows: [Row] = [
        // MinimedKit/PumpEvents/PumpAlarmPumpEvent.swift:53
        Row(
            identifier: "PumpAlarmType.autoOff",
            message: "Auto-Off Alarm",
            role: "errorMessage",
            taxonomy: "N1",
            expected: .other("Auto-Off Alarm")
        ),
        // MinimedKit/PumpEvents/PumpAlarmPumpEvent.swift:55
        Row(
            identifier: "PumpAlarmType.batteryOutLimitExceeded",
            message: "Battery Out Limit",
            role: "errorMessage",
            taxonomy: "N5",
            expected: .other("Battery Out Limit")
        ),
        // MinimedKit/PumpEvents/PumpAlarmPumpEvent.swift:57
        Row(
            identifier: "PumpAlarmType.noDelivery",
            message: "No Delivery Alarm",
            role: "errorMessage",
            taxonomy: "N1",
            expected: .other("No Delivery Alarm")
        ),
        // MinimedKit/PumpEvents/PumpAlarmPumpEvent.swift:59
        Row(
            identifier: "PumpAlarmType.batteryDepleted",
            message: "Battery Depleted",
            role: "errorMessage",
            taxonomy: "N5",
            expected: .other("Battery Depleted")
        ),
        // MinimedKit/PumpEvents/PumpAlarmPumpEvent.swift:61
        Row(
            identifier: "PumpAlarmType.deviceReset",
            message: "Device Reset",
            role: "errorMessage",
            taxonomy: "N1",
            expected: .other("Device Reset")
        ),
        // MinimedKit/PumpEvents/PumpAlarmPumpEvent.swift:63
        Row(
            identifier: "PumpAlarmType.deviceResetBatteryIssue17",
            message: "BatteryIssue17",
            role: "errorMessage",
            taxonomy: "N1",
            expected: .other("BatteryIssue17")
        ),
        // MinimedKit/PumpEvents/PumpAlarmPumpEvent.swift:65
        Row(
            identifier: "PumpAlarmType.deviceResetBatteryIssue21",
            message: "BatteryIssue21",
            role: "errorMessage",
            taxonomy: "N1",
            expected: .other("BatteryIssue21")
        ),
        // MinimedKit/PumpEvents/PumpAlarmPumpEvent.swift:67
        Row(
            identifier: "PumpAlarmType.reprogramError",
            message: "Reprogram Error",
            role: "errorMessage",
            taxonomy: "N1",
            expected: .other("Reprogram Error")
        ),
        // MinimedKit/PumpEvents/PumpAlarmPumpEvent.swift:69
        Row(
            identifier: "PumpAlarmType.emptyReservoir",
            message: "Empty Reservoir",
            role: "errorMessage",
            taxonomy: "N4",
            expected: .other("Empty Reservoir")
        ),
        // MinimedKit/PumpEvents/PumpAlarmPumpEvent.swift:71
        Row(
            identifier: "PumpAlarmType.unknownType",
            message: "Unknown Alarm",
            role: "errorMessage",
            taxonomy: "N1",
            expected: .other("Unknown Alarm")
        ),
        // MinimedKit/PumpManager/DoseStore.swift:133
        Row(
            identifier: "ClearAlarmPumpEvent",
            message: "Clear Alarm",
            role: "errorMessage",
            taxonomy: "N14",
            expected: .other("Clear Alarm")
        ),
        // MinimedKit/PumpManager/DoseStore.swift:144
        Row(
            identifier: "JournalEntryPumpLowBatteryPumpEvent",
            message: "Low Battery",
            role: "errorMessage",
            taxonomy: "F2",
            expected: .other("Low Battery")
        ),
        // MinimedKit/PumpManager/DoseStore.swift:147
        Row(
            identifier: "JournalEntryPumpLowReservoirPumpEvent",
            message: "Low Reservoir",
            role: "errorMessage",
            taxonomy: "F1",
            expected: .other("Low Reservoir")
        ),
        // MinimedKit/Messages/PumpErrorMessageBody.swift:21
        Row(
            identifier: "PumpErrorCode.commandRefused",
            message: "Command refused",
            role: "errorMessage",
            taxonomy: "N9",
            expected: .other("Command refused")
        ),
        // MinimedKit/Messages/PumpErrorMessageBody.swift:21
        Row(
            identifier: "PumpErrorCode.commandRefused",
            message: "Check that the pump is not suspended or priming, or has a percent temp basal type",
            role: "errorMessage",
            taxonomy: "N9",
            expected: .other("Check that the pump is not suspended or priming, or has a percent temp basal type")
        ),
        // MinimedKit/Messages/PumpErrorMessageBody.swift:23
        Row(
            identifier: "PumpErrorCode.maxSettingExceeded",
            message: "Max setting exceeded",
            role: "errorMessage",
            taxonomy: "N9",
            expected: .other("Max setting exceeded")
        ),
        // MinimedKit/Messages/PumpErrorMessageBody.swift:25
        Row(
            identifier: "PumpErrorCode.bolusInProgress",
            message: "Bolus in progress",
            role: "errorMessage",
            taxonomy: "N9",
            expected: .other("Bolus in progress")
        ),
        // MinimedKit/Messages/PumpErrorMessageBody.swift:27
        Row(
            identifier: "PumpErrorCode.pageDoesNotExist",
            message: "History page does not exist",
            role: "errorMessage",
            taxonomy: "N9",
            expected: .other("History page does not exist")
        ),
        // MinimedKit/PumpManager/MinimedPumpMessageSender.swift:90
        Row(
            identifier: "PumpOpsError.unknownPumpErrorCode",
            message: "Unknown pump error code: %1$@",
            role: "errorMessage",
            taxonomy: "N9",
            expected: .other("Unknown pump error code: %1$@")
        ),
        // MinimedKit/PumpManager/PumpOpsError.swift:41
        Row(
            identifier: "PumpOpsError.bolusInProgress",
            message: "A bolus is already in progress",
            role: "errorMessage",
            taxonomy: "N9",
            expected: .other("A bolus is already in progress")
        ),
        // MinimedKit/PumpManager/PumpOpsError.swift:43
        Row(
            identifier: "PumpOpsError.couldNotDecode",
            message: "Invalid response during %1$@: %2$@",
            role: "errorMessage",
            taxonomy: "N8",
            expected: .other("Invalid response during %1$@: %2$@")
        ),
        // MinimedKit/PumpManager/PumpOpsError.swift:45
        Row(
            identifier: "PumpOpsError.crosstalk",
            message: "Comms with another pump detected",
            role: "errorMessage",
            taxonomy: "N8",
            expected: .commsTransient
        ),
        // MinimedKit/PumpManager/PumpOpsError.swift:47
        Row(
            identifier: "PumpOpsError.noResponse",
            message: "Pump did not respond",
            role: "errorMessage",
            taxonomy: "N8",
            expected: .other("Pump did not respond")
        ),
        // MinimedKit/PumpManager/PumpOpsError.swift:49
        Row(
            identifier: "PumpOpsError.pumpSuspended",
            message: "Pump is suspended",
            role: "errorMessage",
            taxonomy: "N9",
            expected: .other("Pump is suspended")
        ),
        // MinimedKit/PumpManager/PumpOpsError.swift:53
        Row(
            identifier: "PumpOpsError.unexpectedResponse",
            message: "Unexpected response %1$@",
            role: "errorMessage",
            taxonomy: "N8",
            expected: .other("Unexpected response %1$@")
        ),
        // MinimedKit/PumpManager/PumpOpsError.swift:55
        Row(
            identifier: "PumpOpsError.unknownPumpErrorCode",
            message: "Unknown pump error code: %1$@",
            role: "errorMessage",
            taxonomy: "N9",
            expected: .other("Unknown pump error code: %1$@")
        ),
        // MinimedKit/PumpManager/PumpOpsError.swift:57
        Row(
            identifier: "PumpOpsError.unknownPumpModel",
            message: "Unknown pump model: %@",
            role: "errorMessage",
            taxonomy: "N9",
            expected: .other("Unknown pump model: %@")
        ),
        // MinimedKit/PumpManager/PumpOpsError.swift:59
        Row(
            identifier: "PumpOpsError.unknownResponse",
            message: "Unknown response during %1$@: %2$@",
            role: "errorMessage",
            taxonomy: "N8",
            expected: .other("Unknown response during %1$@: %2$@")
        ),
        // MinimedKit/PumpManager/PumpOpsSession.swift:939
        Row(
            identifier: "PumpOpsError.rfCommsFailure",
            message: "No pump responses during scan",
            role: "errorMessage",
            taxonomy: "N8",
            expected: .other("No pump responses during scan")
        ),
        // MinimedKit/PumpManager/PumpOpsSession.swift:554
        Row(
            identifier: "PumpOpsError.rfCommsFailure",
            message: "Confirmed that temp basal failed, and ",
            role: "errorMessage",
            taxonomy: "N9",
            expected: .other("Confirmed that temp basal failed, and ")
        ),
        // MinimedKit/PumpManager/PumpOpsSession.swift:1042
        Row(
            identifier: "PumpOpsError.rfCommsFailure",
            message: "Short history page: (n) bytes. Expected 1024",
            role: "errorMessage",
            taxonomy: "N8",
            expected: .other("Short history page: (n) bytes. Expected 1024")
        ),
        // MinimedKit/PumpManager/PumpOpsSession.swift:1149
        Row(
            identifier: "PumpOpsError.rfCommsFailure",
            message: "Short glucose history page: (n) bytes. Expected 1024",
            role: "errorMessage",
            taxonomy: "N8",
            expected: .other("Short glucose history page: (n) bytes. Expected 1024")
        ),
        // MinimedKit/PumpManager/MinimedPumpManagerError.swift:26
        Row(
            identifier: "MinimedPumpManagerError.noRileyLink",
            message: "No RileyLink Connected",
            role: "errorMessage",
            taxonomy: "N8",
            expected: .other("No RileyLink Connected")
        ),
        // MinimedKit/PumpManager/MinimedPumpManagerError.swift:26
        Row(
            identifier: "MinimedPumpManagerError.noRileyLink",
            message: "Make sure your RileyLink is nearby and powered on",
            role: "errorMessage",
            taxonomy: "N8",
            expected: .other("Make sure your RileyLink is nearby and powered on")
        ),
        // MinimedKit/PumpManager/MinimedPumpManagerError.swift:28
        Row(
            identifier: "MinimedPumpManagerError.bolusInProgress",
            message: "Bolus in Progress",
            role: "errorMessage",
            taxonomy: "N9",
            expected: .other("Bolus in Progress")
        ),
        // MinimedKit/PumpManager/MinimedPumpManagerError.swift:30
        Row(
            identifier: "MinimedPumpManagerError.pumpSuspended",
            message: "Pump is Suspended",
            role: "errorMessage",
            taxonomy: "N9",
            expected: .other("Pump is Suspended")
        ),
        // MinimedKit/PumpManager/MinimedPumpManagerError.swift:32
        Row(
            identifier: "MinimedPumpManagerError.insulinTypeNotConfigured",
            message: "Insulin Type is not configured",
            role: "errorMessage",
            taxonomy: "N13",
            expected: .other("Insulin Type is not configured")
        ),
        // MinimedKit/PumpManager/MinimedPumpManagerError.swift:32
        Row(
            identifier: "MinimedPumpManagerError.insulinTypeNotConfigured",
            message: "Go to pump settings and select insulin type",
            role: "errorMessage",
            taxonomy: "N13",
            expected: .other("Go to pump settings and select insulin type")
        ),
        // MinimedKit/PumpManager/MinimedPumpManagerError.swift:36
        Row(
            identifier: "MinimedPumpManagerError.tuneFailed",
            message: "RileyLink radio tune failed: (underlying error)",
            role: "errorMessage",
            taxonomy: "N8",
            expected: .other("RileyLink radio tune failed: (underlying error)")
        ),
        // MinimedKit/PumpManager/MinimedPumpManagerError.swift:40
        Row(
            identifier: "MinimedPumpManagerError.storageFailure",
            message: "Unable to store pump data",
            role: "errorMessage",
            taxonomy: "N9",
            expected: .other("Unable to store pump data")
        ),
        // MinimedKit/PumpManager/PumpOpsSession.swift:30
        Row(
            identifier: "SetBolusError.uncertain",
            message: "Bolus may have failed: %1$@",
            role: "errorMessage",
            taxonomy: "N3",
            expected: .deliveryUncertain
        ),
        // MinimedKit/PumpManager/PumpOpsSession.swift:30
        Row(
            identifier: "SetBolusError.uncertain",
            message: "Please check your pump bolus history to determine if the bolus was delivered.",
            role: "errorMessage",
            taxonomy: "N3",
            expected: .other("Please check your pump bolus history to determine if the bolus was delivered.")
        ),
        // MinimedKit/PumpManager/PumpOpsSession.swift:30
        Row(
            identifier: "SetBolusError.uncertain",
            message: "Loop sent a bolus command to the pump, but was unable to confirm…",
            role: "errorMessage",
            taxonomy: "N3",
            expected: .other("Loop sent a bolus command to the pump, but was unable to confirm…")
        ),
        // MinimedKit/Messages/Models/HistoryPage.swift:21
        Row(
            identifier: "HistoryPageError.invalidCRC",
            message: "History page failed crc check",
            role: "errorMessage",
            taxonomy: "N8",
            expected: .other("History page failed crc check")
        ),
        // MinimedKit/Messages/Models/HistoryPage.swift:23
        Row(
            identifier: "HistoryPageError.unknownEventType",
            message: "Unknown history record type: %$1@",
            role: "errorMessage",
            taxonomy: "N8",
            expected: .other("Unknown history record type: %$1@")
        ),
        // MinimedKit/Messages/Models/GlucosePage.swift:20
        Row(
            identifier: "GlucosePageError.invalidCRC",
            message: "Glucose page failed crc check",
            role: "errorMessage",
            taxonomy: "N11",
            expected: .other("Glucose page failed crc check")
        ),
        // MinimedKit/PumpManager/MinimedPumpManager.swift:263-268
        Row(
            identifier: "lowRLBattery",
            message: "Low RileyLink Battery",
            role: "alertTitle",
            taxonomy: "F2",
            expected: .other("Low RileyLink Battery")
        ),
        // MinimedKit/PumpManager/MinimedPumpManager.swift:263-268
        Row(
            identifier: "lowRLBattery",
            message: "\"%1$@\" has a low battery",
            role: "alertBody",
            taxonomy: "F2",
            expected: .other("\"%1$@\" has a low battery")
        ),
        // MinimedKit/PumpManager/MinimedPumpManager.swift:495-510
        Row(
            identifier: "PumpBatteryLow",
            message: "Pump Battery Low",
            role: "alertTitle",
            taxonomy: "F2",
            expected: .other("Pump Battery Low")
        ),
        // MinimedKit/PumpManager/MinimedPumpManager.swift:495-510
        Row(
            identifier: "PumpBatteryLow",
            message: "Change the pump battery immediately",
            role: "alertBody",
            taxonomy: "F2",
            expected: .other("Change the pump battery immediately")
        ),
        // MinimedKit/PumpManager/MinimedPumpManager.swift:560-600
        Row(
            identifier: "PumpReservoirEmpty",
            message: "Pump Reservoir Empty",
            role: "alertTitle",
            taxonomy: "N4",
            expected: .other("Pump Reservoir Empty")
        ),
        // MinimedKit/PumpManager/MinimedPumpManager.swift:560-600
        Row(
            identifier: "PumpReservoirEmpty",
            message: "Change the pump reservoir now",
            role: "alertBody",
            taxonomy: "N4",
            expected: .other("Change the pump reservoir now")
        ),
        // MinimedKit/PumpManager/MinimedPumpManager.swift:571-610
        Row(
            identifier: "PumpReservoirLow",
            message: "Pump Reservoir Low",
            role: "alertTitle",
            taxonomy: "F1",
            expected: .other("Pump Reservoir Low")
        ),
        // MinimedKit/PumpManager/MinimedPumpManager.swift:571-610
        Row(
            identifier: "PumpReservoirLow",
            message: "%1$@ U left: %2$@",
            role: "alertBody",
            taxonomy: "F1",
            expected: .other("%1$@ U left: %2$@")
        ),
        // MinimedKit/PumpManager/MinimedPumpManager.swift:571-610
        Row(
            identifier: "PumpReservoirLow",
            message: "%1$@ U left",
            role: "alertBody",
            taxonomy: "F1",
            expected: .other("%1$@ U left")
        ),
        // MinimedKit/PumpManager/MinimedPumpManager.swift:468
        Row(
            identifier: "PumpStatusHighlight.suspended",
            message: "Insulin Suspended",
            role: "notificationBody",
            taxonomy: "N2",
            expected: .other("Insulin Suspended")
        ),
        // MinimedKit/PumpManager/MinimedPumpManager.swift:475
        Row(
            identifier: "PumpStatusHighlight.signalLoss",
            message: "Signal Loss",
            role: "notificationBody",
            taxonomy: "N8",
            expected: .other("Signal Loss")
        ),
        // MinimedKitUI/Views/MinimedPumpSettingsViewModel.swift:148
        Row(
            identifier: "MinimedSettingsViewAlert.resumeError",
            message: "Error Resuming",
            role: "alertTitle",
            taxonomy: "N9",
            expected: .other("Error Resuming")
        ),
        // MinimedKitUI/Views/MinimedPumpSettingsViewModel.swift:157
        Row(
            identifier: "MinimedSettingsViewAlert.suspendError",
            message: "Error Suspending",
            role: "alertTitle",
            taxonomy: "N9",
            expected: .other("Error Suspending")
        ),
        // MinimedKitUI/Views/MinimedPumpSettingsViewModel.swift:250
        Row(
            identifier: "MinimedSettingsViewAlert.syncTimeError",
            message: "Error Syncing Time",
            role: "alertTitle",
            taxonomy: "N9",
            expected: .other("Error Syncing Time")
        ),
        // MinimedKitUI/Views/MinimedPumpSettingsView.swift:324-333
        Row(
            identifier: "MinimedPumpSettingsView.timeChangeActionSheet",
            message: "Time Change Detected",
            role: "alertTitle",
            taxonomy: "N14",
            expected: .other("Time Change Detected")
        ),
        // MinimedKitUI/Views/MinimedPumpSettingsView.swift:324-333
        Row(
            identifier: "MinimedPumpSettingsView.timeChangeActionSheet",
            message: "The time on your pump is different from the current time. Do you want to update the time on your pump to the current time?",
            role: "alertBody",
            taxonomy: "N14",
            expected: .other(
                "The time on your pump is different from the current time. Do you want to update the time on your pump to the current time?"
            )
        )
    ]

    // MARK: - Classification (pinned to CURRENT, must be green)

    @Test("each (identifier, message) classifies as pinned", arguments: rows) func eachMessageClassifiesAsPinned(_ row: Row) {
        #expect(TrioAlertClassifier.categorize(error: StubError(description: row.message)) == row.expected)
    }

    // MARK: - Classifier coverage gaps (ratchet)

    /// "identifier — message" keys for rows whose DISPLAY string falls through
    /// to `.other` today even though its taxonomy bucket is a real category the
    /// classifier *could* map. Each entry names the bucket it SHOULD hit and
    /// why the substring classifier misses it (the spaced prose never contains
    /// the concatenated token the classifier looks for):
    ///
    ///  - "PumpAlarmType.noDelivery — No Delivery Alarm": SHOULD be `.occlusion`
    ///    (N1). Classifier looks for "occlusion"/"occluded"; the title has
    ///    neither. MinimedKit/PumpEvents/PumpAlarmPumpEvent.swift:57
    ///  - "PumpAlarmType.autoOff — Auto-Off Alarm",
    ///    "PumpAlarmType.deviceReset — Device Reset",
    ///    "PumpAlarmType.deviceResetBatteryIssue17 — BatteryIssue17",
    ///    "PumpAlarmType.deviceResetBatteryIssue21 — BatteryIssue21",
    ///    "PumpAlarmType.reprogramError — Reprogram Error",
    ///    "PumpAlarmType.unknownType — Unknown Alarm": SHOULD be
    ///    `.hardwareFault` (N1). Classifier looks for "fault"/"patchfault";
    ///    none of these titles contain it.
    ///    MinimedKit/PumpEvents/PumpAlarmPumpEvent.swift:53-71
    ///  - "PumpAlarmType.emptyReservoir — Empty Reservoir",
    ///    "PumpReservoirEmpty — Pump Reservoir Empty",
    ///    "PumpReservoirEmpty — Change the pump reservoir now": SHOULD be
    ///    `.reservoirEmpty` (N4). Classifier looks for the concatenated tokens
    ///    "reservoirempty"/"emptyreservoir"; the spaced prose ("empty
    ///    reservoir", "reservoir empty") contains neither.
    ///    PumpAlarmPumpEvent.swift:69; MinimedPumpManager.swift:560-600
    ///  - "JournalEntryPumpLowReservoirPumpEvent — Low Reservoir",
    ///    "PumpReservoirLow — Pump Reservoir Low",
    ///    "PumpReservoirLow — %1$@ U left: %2$@",
    ///    "PumpReservoirLow — %1$@ U left": SHOULD be `.reservoirLow` (F1).
    ///    Classifier looks for "lowreservoir"; "low reservoir"/"reservoir low"
    ///    (and the formatted bodies) never contain it.
    ///    DoseStore.swift:147; MinimedPumpManager.swift:571-610
    ///  - comms/transient rows that SHOULD be `.commsTransient` (N8) but miss
    ///    because the classifier wants "communication"/"comms"/"notconnected"/
    ///    "noresponse"/"timeout"/"rssi" and the prose never spells those tokens
    ///    contiguously:
    ///      "PumpOpsError.couldNotDecode — Invalid response during %1$@: %2$@",
    ///      "PumpOpsError.noResponse — Pump did not respond" (spaced, not
    ///        "noresponse"),
    ///      "PumpOpsError.unexpectedResponse — Unexpected response %1$@",
    ///      "PumpOpsError.unknownResponse — Unknown response during %1$@: %2$@",
    ///      "PumpOpsError.rfCommsFailure — No pump responses during scan",
    ///      "PumpOpsError.rfCommsFailure — Short history page: (n) bytes. Expected 1024",
    ///      "PumpOpsError.rfCommsFailure — Short glucose history page: (n) bytes. Expected 1024",
    ///      "MinimedPumpManagerError.noRileyLink — No RileyLink Connected"
    ///        ("not connected" is two words, not "notconnected"),
    ///      "MinimedPumpManagerError.noRileyLink — Make sure your RileyLink is nearby and powered on",
    ///      "MinimedPumpManagerError.tuneFailed — RileyLink radio tune failed: (underlying error)",
    ///      "HistoryPageError.invalidCRC — History page failed crc check",
    ///      "HistoryPageError.unknownEventType — Unknown history record type: %$1@",
    ///      "PumpStatusHighlight.signalLoss — Signal Loss".
    ///    Sources: PumpOpsError.swift:43-59; PumpOpsSession.swift:554-1149;
    ///    MinimedPumpManagerError.swift:26-36; HistoryPage.swift:21-23;
    ///    MinimedPumpManager.swift:475
    ///  - "SetBolusError.uncertain — Please check your pump bolus history to
    ///    determine if the bolus was delivered.",
    ///    "SetBolusError.uncertain — Loop sent a bolus command to the pump, but
    ///    was unable to confirm…": SHOULD be `.deliveryUncertain` (N3). Only the
    ///    sibling "Bolus may have failed: …" string matches (the classifier
    ///    special-cases that exact spaced phrase); these accompanying bodies do
    ///    not contain "bolus may have failed"/"uncertaindelivery"/
    ///    "unacknowledged". MinimedKit/PumpManager/PumpOpsSession.swift:30
    ///
    /// Stays green now (pins the misses); FAILS — forcing this file to be
    /// updated — once the classifier is improved to map these messages.
    static let classifierCoverageGaps: Set<String> = [
        "PumpAlarmType.autoOff — Auto-Off Alarm",
        "PumpAlarmType.noDelivery — No Delivery Alarm",
        "PumpAlarmType.deviceReset — Device Reset",
        "PumpAlarmType.deviceResetBatteryIssue17 — BatteryIssue17",
        "PumpAlarmType.deviceResetBatteryIssue21 — BatteryIssue21",
        "PumpAlarmType.reprogramError — Reprogram Error",
        "PumpAlarmType.emptyReservoir — Empty Reservoir",
        "PumpAlarmType.unknownType — Unknown Alarm",
        "JournalEntryPumpLowReservoirPumpEvent — Low Reservoir",
        "PumpOpsError.couldNotDecode — Invalid response during %1$@: %2$@",
        "PumpOpsError.noResponse — Pump did not respond",
        "PumpOpsError.unexpectedResponse — Unexpected response %1$@",
        "PumpOpsError.unknownResponse — Unknown response during %1$@: %2$@",
        "PumpOpsError.rfCommsFailure — No pump responses during scan",
        "PumpOpsError.rfCommsFailure — Short history page: (n) bytes. Expected 1024",
        "PumpOpsError.rfCommsFailure — Short glucose history page: (n) bytes. Expected 1024",
        "MinimedPumpManagerError.noRileyLink — No RileyLink Connected",
        "MinimedPumpManagerError.noRileyLink — Make sure your RileyLink is nearby and powered on",
        "MinimedPumpManagerError.tuneFailed — RileyLink radio tune failed: (underlying error)",
        "SetBolusError.uncertain — Please check your pump bolus history to determine if the bolus was delivered.",
        "SetBolusError.uncertain — Loop sent a bolus command to the pump, but was unable to confirm…",
        "HistoryPageError.invalidCRC — History page failed crc check",
        "HistoryPageError.unknownEventType — Unknown history record type: %$1@",
        "PumpReservoirEmpty — Pump Reservoir Empty",
        "PumpReservoirEmpty — Change the pump reservoir now",
        "PumpReservoirLow — Pump Reservoir Low",
        "PumpReservoirLow — %1$@ U left: %2$@",
        "PumpReservoirLow — %1$@ U left",
        "PumpStatusHighlight.signalLoss — Signal Loss"
    ]

    /// Taxonomy bucket each row was intended to map to (from the audit). A row
    /// is a gap when it currently falls to `.other(message)` yet its taxonomy
    /// bucket is something other than "other".
    static let taxonomyBuckets: [String: String] = [
        "PumpAlarmType.autoOff — Auto-Off Alarm": "hardwareFault",
        "PumpAlarmType.batteryOutLimitExceeded — Battery Out Limit": "other",
        "PumpAlarmType.noDelivery — No Delivery Alarm": "occlusion",
        "PumpAlarmType.batteryDepleted — Battery Depleted": "other",
        "PumpAlarmType.deviceReset — Device Reset": "hardwareFault",
        "PumpAlarmType.deviceResetBatteryIssue17 — BatteryIssue17": "hardwareFault",
        "PumpAlarmType.deviceResetBatteryIssue21 — BatteryIssue21": "hardwareFault",
        "PumpAlarmType.reprogramError — Reprogram Error": "hardwareFault",
        "PumpAlarmType.emptyReservoir — Empty Reservoir": "reservoirEmpty",
        "PumpAlarmType.unknownType — Unknown Alarm": "hardwareFault",
        "ClearAlarmPumpEvent — Clear Alarm": "other",
        "JournalEntryPumpLowBatteryPumpEvent — Low Battery": "other",
        "JournalEntryPumpLowReservoirPumpEvent — Low Reservoir": "reservoirLow",
        "PumpErrorCode.commandRefused — Command refused": "other",
        "PumpErrorCode.commandRefused — Check that the pump is not suspended or priming, or has a percent temp basal type": "other",
        "PumpErrorCode.maxSettingExceeded — Max setting exceeded": "other",
        "PumpErrorCode.bolusInProgress — Bolus in progress": "other",
        "PumpErrorCode.pageDoesNotExist — History page does not exist": "other",
        "PumpOpsError.unknownPumpErrorCode — Unknown pump error code: %1$@": "other",
        "PumpOpsError.bolusInProgress — A bolus is already in progress": "other",
        "PumpOpsError.couldNotDecode — Invalid response during %1$@: %2$@": "commsTransient",
        "PumpOpsError.crosstalk — Comms with another pump detected": "commsTransient",
        "PumpOpsError.noResponse — Pump did not respond": "commsTransient",
        "PumpOpsError.pumpSuspended — Pump is suspended": "other",
        "PumpOpsError.unexpectedResponse — Unexpected response %1$@": "commsTransient",
        "PumpOpsError.unknownPumpModel — Unknown pump model: %@": "other",
        "PumpOpsError.unknownResponse — Unknown response during %1$@: %2$@": "commsTransient",
        "PumpOpsError.rfCommsFailure — No pump responses during scan": "commsTransient",
        "PumpOpsError.rfCommsFailure — Confirmed that temp basal failed, and ": "other",
        "PumpOpsError.rfCommsFailure — Short history page: (n) bytes. Expected 1024": "commsTransient",
        "PumpOpsError.rfCommsFailure — Short glucose history page: (n) bytes. Expected 1024": "commsTransient",
        "MinimedPumpManagerError.noRileyLink — No RileyLink Connected": "commsTransient",
        "MinimedPumpManagerError.noRileyLink — Make sure your RileyLink is nearby and powered on": "commsTransient",
        "MinimedPumpManagerError.bolusInProgress — Bolus in Progress": "other",
        "MinimedPumpManagerError.pumpSuspended — Pump is Suspended": "other",
        "MinimedPumpManagerError.insulinTypeNotConfigured — Insulin Type is not configured": "other",
        "MinimedPumpManagerError.insulinTypeNotConfigured — Go to pump settings and select insulin type": "other",
        "MinimedPumpManagerError.tuneFailed — RileyLink radio tune failed: (underlying error)": "commsTransient",
        "MinimedPumpManagerError.storageFailure — Unable to store pump data": "other",
        "SetBolusError.uncertain — Bolus may have failed: %1$@": "deliveryUncertain",
        "SetBolusError.uncertain — Please check your pump bolus history to determine if the bolus was delivered.": "deliveryUncertain",
        "SetBolusError.uncertain — Loop sent a bolus command to the pump, but was unable to confirm…": "deliveryUncertain",
        "HistoryPageError.invalidCRC — History page failed crc check": "commsTransient",
        "HistoryPageError.unknownEventType — Unknown history record type: %$1@": "commsTransient",
        "GlucosePageError.invalidCRC — Glucose page failed crc check": "other",
        "lowRLBattery — Low RileyLink Battery": "other",
        "lowRLBattery — \"%1$@\" has a low battery": "other",
        "PumpBatteryLow — Pump Battery Low": "other",
        "PumpBatteryLow — Change the pump battery immediately": "other",
        "PumpReservoirEmpty — Pump Reservoir Empty": "reservoirEmpty",
        "PumpReservoirEmpty — Change the pump reservoir now": "reservoirEmpty",
        "PumpReservoirLow — Pump Reservoir Low": "reservoirLow",
        "PumpReservoirLow — %1$@ U left: %2$@": "reservoirLow",
        "PumpReservoirLow — %1$@ U left": "reservoirLow",
        "PumpStatusHighlight.suspended — Insulin Suspended": "other",
        "PumpStatusHighlight.signalLoss — Signal Loss": "commsTransient",
        "MinimedSettingsViewAlert.resumeError — Error Resuming": "other",
        "MinimedSettingsViewAlert.suspendError — Error Suspending": "other",
        "MinimedSettingsViewAlert.syncTimeError — Error Syncing Time": "other",
        "MinimedPumpSettingsView.timeChangeActionSheet — Time Change Detected": "other",
        "MinimedPumpSettingsView.timeChangeActionSheet — The time on your pump is different from the current time. Do you want to update the time on your pump to the current time?": "other"
    ]

    @Test("classifier coverage gaps are exactly as documented") func classifierCoverageGapsExact() {
        let computed = Set(
            Self.rows
                .filter { row in
                    let bucket = Self.taxonomyBuckets["\(row.identifier) — \(row.message)"] ?? "other"
                    return row.expected == .other(row.message) && bucket != "other"
                }
                .map { "\($0.identifier) — \($0.message)" }
        )
        #expect(computed == Self.classifierCoverageGaps)
    }
}
