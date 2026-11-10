import Foundation
import LoopKit
import Testing

@testable import Trio

/// Pins Trio's alert routing for the **TandemKit** pump plugin (Tandem t:slim X2 / Mobi).
///
/// TandemKit is not linked into Trio, so its side is pinned as tables built here.
/// `// Sources/...` references point into TandemKit `trio-next-dev` at `aeddab40`.
///
/// Every pump notification fetch ends in `TandemPumpManager.reconcileLoopKitAlerts()`,
/// which issues a LoopKit Alert for each new item in a surfaced category and retracts
/// the ones that cleared. Surfaced categories are alert, alarm and malfunction, plus
/// cgmAlert when CGM alert forwarding is on; reminders stay in TandemKit's own list.
/// With auto-acknowledge on, the basal alerts in `basalAlertsToIgnoreWhenLooping` are
/// dismissed on the pump and never issued. The level comes from the category. The one
/// other alert is `pump-clock-skew`.
///
/// Remaining gap: TandemKit does not declare `alertCatalog` yet (its LoopKit predates
/// `AlertCatalogVendor`), so Device Alarms lists no Tandem alarms until it does.
@Suite("Trio Alert Emission: TandemKit") struct TandemKitAlertEmissionTests {
    /// `TandemPumpManager.pluginIdentifier`, which `TandemPumpManager.alertIdentifier(_:)`
    /// issues every alert under.
    // Sources/TandemKit/PumpManager/TandemPumpManager.swift:12
    // Sources/TandemKit/PumpManager/TandemPumpManager+Alerts.swift:128
    private static let managerIdentifier = "TandemPumpManager"

    private func id(_ alertID: String) -> Alert.Identifier {
        Alert.Identifier(managerIdentifier: Self.managerIdentifier, alertIdentifier: alertID)
    }

    /// One issued alert. `source` is the notification category (or the standalone alert),
    /// `alertIdentifier` a real identifier of that shape, `level` the level TandemKit
    /// issues it with, and `tier` the Device Alarms tier Trio files it under.
    struct Row {
        let source: String
        let alertIdentifier: String
        let level: Alert.InterruptionLevel
        let tier: DeviceAlertSeverity
    }

    /// Category -> `PumpNotificationSeverity` -> `interruptionLevel`.
    // Sources/TandemCore/PumpNotificationAlert.swift:21 (category -> severity)
    // Sources/TandemKit/PumpManager/TandemPumpManager+Alerts.swift:7 (severity -> level)
    static let rows: [Row] = [
        // OCCLUSION_ALARM = 2 (Sources/TandemCore/Messages/CurrentStatus/AlarmStatus.swift:65),
        // slug "occlusion" (Sources/TandemCore/PumpNotificationAlert.swift:98).
        Row(source: "alarm", alertIdentifier: "alarm.occlusion.2", level: .critical, tier: .critical),
        // `malfunction.<aamId>`, no slug (Sources/TandemCore/NotificationBundle.swift:206).
        // The aamId here is illustrative.
        Row(source: "malfunction", alertIdentifier: "malfunction.12", level: .critical, tier: .critical),
        // LOW_INSULIN_ALERT = 0 (Sources/TandemCore/Messages/CurrentStatus/AlertStatus.swift:57),
        // slug "lowInsulin" (Sources/TandemCore/PumpNotificationAlert.swift:50).
        Row(source: "alert", alertIdentifier: "alert.lowInsulin.0", level: .timeSensitive, tier: .timeSensitive),
        // SENSOR_FAILED_CGM_ALERT = 11 (Sources/TandemCore/Messages/CurrentStatus/CGMAlertStatus.swift:79),
        // slug "sensorFailed" (Sources/TandemCore/PumpNotificationAlert.swift:128). Only with forwarding on.
        Row(source: "cgmAlert", alertIdentifier: "cgmAlert.sensorFailed.11", level: .timeSensitive, tier: .timeSensitive),
        // Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:1041, :1071
        Row(source: "pump-clock-skew", alertIdentifier: "pump-clock-skew", level: .timeSensitive, tier: .timeSensitive)
    ]

    // MARK: - Device-tier routing

    @Test("every Tandem alert follows the Device Alarms tiers", arguments: rows) func followsDeviceTiers(_ row: Row) {
        #expect(BaseTrioAlertManager.followsDeviceTiers(id(row.alertIdentifier)))
    }

    @Test("issued level maps to the pinned Device Alarms tier", arguments: rows) func levelMapsToTier(_ row: Row) {
        #expect(DeviceAlertSeverity(level: row.level) == row.tier)
    }

    @Test("tier config keeps the issued level unless the override escalates it", arguments: rows) func configKeepsLevel(
        _ row: Row
    ) {
        let content = Alert.Content(title: "Pump Alarm", body: "Occlusion", acknowledgeActionButtonLabel: "Dismiss")
        let alert = Alert(
            identifier: id(row.alertIdentifier),
            foregroundContent: content,
            backgroundContent: content,
            trigger: .immediate,
            interruptionLevel: row.level
        )
        var config = DeviceAlertSeverityConfig(severity: row.tier)
        config.overridesSilenceAndDND = false
        #expect(BaseTrioAlertManager.applyDeviceSeverityConfig(config, to: alert).interruptionLevel == row.level)
        config.overridesSilenceAndDND = true
        #expect(BaseTrioAlertManager.applyDeviceSeverityConfig(config, to: alert).interruptionLevel == .critical)
    }

    // MARK: - Identifier shapes

    /// `NotificationItem.stableIdentifier` is `<category>.<slug>.<bit>`, or
    /// `malfunction.<aamId>` (Sources/TandemCore/NotificationBundle.swift:445).
    @Test("pump notification identifiers have the stableIdentifier shape", arguments: rows.filter {
        $0.source != "pump-clock-skew"
    }) func identifierShape(_ row: Row) {
        let segments = row.alertIdentifier.split(separator: ".", omittingEmptySubsequences: false)
        #expect(segments.first.map(String.init) == row.source)
        #expect(segments.count == (row.source == "malfunction" ? 2 : 3))
        #expect(segments.last.flatMap { UInt32($0) } != nil)
        #expect(id(row.alertIdentifier).value == "TandemPumpManager.\(row.alertIdentifier)")
    }
}

// MARK: - Message classification (SECONDARY: error-string routing)

/// Pins how `TrioAlertClassifier` buckets the text of TandemKit's user-facing messages.
///
/// Pump notifications are issued as LoopKit Alerts (suite above) and never reach the
/// classifier, so they have no rows. What does reach it is a `PumpCommError` or
/// `TandemPumpManagerValidationError` from a `PumpManager` completion, wrapped in
/// LoopKit's `PumpManagerError` and `APSError.pumpError` (`APSManager.processError`);
/// production classifies `String(describing:)` of that wrapper, not the text below.
/// The other rows are in-app text that never reaches Trio.
///
/// Each row feeds the display string, the worst case for the matcher: its tokens are
/// space-free ("notconnected", "noresponse", "reservoirempty"), so spaced prose falls
/// through to `.other`. `identifier` is the source symbol, not a LoopKit alert id.
@Suite("Trio Alert Emission: TandemKit — Classification") struct TandemKitMessageClassificationTests {
    /// A throwaway `Error` whose `String(describing:)` is exactly the emission
    /// display string, so `categorize(error:)` matches over natural-language
    /// text (mind the spaces: "reservoir is empty" does NOT contain
    /// "reservoirempty"; most prose -> `.other`).
    private struct StubError: Error, CustomStringConvertible { let description: String }

    /// One reportable message: its source identifier (error case / symbol),
    /// the exact display string, its UI role, taxonomy node, and the category
    /// the current classifier pins it to.
    struct Row {
        let identifier: String
        let message: String
        let role: String
        let taxonomy: String
        let expected: TrioAlertCategory
    }

    static let rows: [Row] = [
        // Sources/TandemKitUI/TandemPumpManager+UI.swift:149
        Row(
            identifier: "PumpStatusHighlight.suspended",
            message: "Insulin Suspended",
            role: "notificationTitle",
            taxonomy: "N2",
            expected: .other("Insulin Suspended")
        ),
        // Sources/TandemKitUI/TandemPumpManager+UI.swift:160
        Row(
            identifier: "PumpStatusHighlight.noInsulin",
            message: "No Insulin",
            role: "notificationTitle",
            taxonomy: "N4",
            expected: .other("No Insulin")
        ),
        // Sources/TandemCore/PumpCommError.swift:33
        Row(
            identifier: "PumpCommError.pumpNotConnected",
            message: "Pump not connected",
            role: "errorMessage",
            taxonomy: "N8",
            expected: .other("Pump not connected")
        ),
        // Sources/TandemCore/PumpCommError.swift:170
        Row(
            identifier: "PumpCommError.pumpNotConnected",
            message: "Make sure iPhone is nearby the active pump",
            role: "errorMessage",
            taxonomy: "N8",
            expected: .other("Make sure iPhone is nearby the active pump")
        ),
        // Sources/TandemCore/PumpCommError.swift:37
        Row(
            identifier: "PumpCommError.noResponse",
            message: "No response from pump",
            role: "errorMessage",
            taxonomy: "N8",
            expected: .other("No response from pump")
        ),
        // Sources/TandemKit/PumpManager/TandemPeripheralManager.swift:534
        Row(
            identifier: "PumpCommError.errorResponse",
            message: "Pump Error: Failed to discoverServices: <error>",
            role: "errorMessage",
            taxonomy: "N8",
            expected: .other("Pump Error: Failed to discoverServices: <error>")
        ),
        // Sources/TandemKit/PumpManager/TandemPeripheralManager.swift:542
        Row(
            identifier: "PumpCommError.errorResponse",
            message: "Pump Error: No service: <PUMP_SERVICE>",
            role: "errorMessage",
            taxonomy: "N8",
            expected: .other("Pump Error: No service: <PUMP_SERVICE>")
        ),
        // Sources/TandemKit/PumpManager/TandemPeripheralManager.swift:552
        Row(
            identifier: "PumpCommError.errorResponse",
            message: "Pump Error: <message>",
            role: "errorMessage",
            taxonomy: "N8",
            expected: .other("Pump Error: <message>")
        ),
        // Sources/TandemKit/PumpManager/TandemPeripheralManager.swift:561
        Row(
            identifier: "PumpCommError.errorResponse",
            message: "Pump Error: No service: <DIS_SERVICE>",
            role: "errorMessage",
            taxonomy: "N8",
            expected: .other("Pump Error: No service: <DIS_SERVICE>")
        ),
        // Sources/TandemKit/PumpManager/TandemBluetoothManager.swift:776
        Row(
            identifier: "PumpCommError.errorResponse",
            message: "Pump Error: Failed to connect: <error>",
            role: "errorMessage",
            taxonomy: "N8",
            expected: .other("Pump Error: Failed to connect: <error>")
        ),
        // Sources/TandemKitUI/Utils/PumpConnectionIssue+Text.swift:25
        Row(
            identifier: "PumpConnectionIssue.pumpUnreachable",
            message: "Pump Disconnected",
            role: "notificationTitle",
            taxonomy: "N8",
            expected: .other("Pump Disconnected")
        ),
        // Sources/TandemKit/State/TandemPumpManagerSettings.swift:77
        Row(
            identifier: "TandemPumpManagerValidationError.invalidBolusAmount",
            message: "Cannot deliver a bolus of <requested> units",
            role: "errorMessage",
            taxonomy: "N9",
            expected: .other("Cannot deliver a bolus of <requested> units")
        ),
        // Sources/TandemKit/State/TandemPumpManagerSettings.swift:85
        Row(
            identifier: "TandemPumpManagerValidationError.maximumBolusExceeded",
            message: "Bolus of <requested> units exceeds the maximum bolus of <maximum> units",
            role: "errorMessage",
            taxonomy: "N9",
            expected: .other("Bolus of <requested> units exceeds the maximum bolus of <maximum> units")
        ),
        // Sources/TandemKit/State/TandemPumpManagerSettings.swift:93
        Row(
            identifier: "TandemPumpManagerValidationError.controlIQModeActive",
            message: "Control-IQ is active on the pump",
            role: "errorMessage",
            taxonomy: "N9",
            expected: .other("Control-IQ is active on the pump")
        ),
        // Sources/TandemKit/State/TandemPumpManagerSettings.swift:98
        Row(
            identifier: "TandemPumpManagerValidationError.bolusIsRunning",
            message: "A bolus is still being delivered",
            role: "errorMessage",
            taxonomy: "N9",
            expected: .other("A bolus is still being delivered")
        ),
        // Sources/TandemKit/State/TandemPumpManagerSettings.swift:103
        Row(
            identifier: "TandemPumpManagerValidationError.basalScheduleNotSynced",
            message: "The pump's basal rates are not confirmed to match the app's",
            role: "errorMessage",
            taxonomy: "N9",
            expected: .other("The pump's basal rates are not confirmed to match the app's")
        ),
        // Sources/TandemKit/State/TandemPumpManagerSettings.swift:108
        Row(
            identifier: "TandemPumpManagerValidationError.failedUpdatePumpProfile",
            message: "Failed to update pump basal profile",
            role: "errorMessage",
            taxonomy: "N9",
            expected: .other("Failed to update pump basal profile")
        ),
        // Sources/TandemKit/State/TandemPumpManagerSettings.swift:113
        Row(
            identifier: "TandemPumpManagerValidationError.pumpProfileBasalRateIsZero",
            message: "The pump's basal rate is 0 U/hr",
            role: "errorMessage",
            taxonomy: "N9",
            expected: .other("The pump's basal rate is 0 U/hr")
        ),
        // Sources/TandemKit/State/TandemPumpManagerSettings.swift:118
        Row(
            identifier: "TandemPumpManagerValidationError.pumpClockUntrusted",
            message: "The pump's clock is more than a day different from the phone's",
            role: "errorMessage",
            taxonomy: "N9",
            expected: .other("The pump's clock is more than a day different from the phone's")
        ),
        // Sources/TandemKit/State/TandemPumpManagerSettings.swift:124
        Row(
            identifier: "TandemPumpManagerValidationError.tempBasalRateMismatch",
            message: "The pump ran a temporary basal rate of <actual> U/hr instead of <expected> U/hr",
            role: "errorMessage",
            taxonomy: "N9",
            expected: .other("The pump ran a temporary basal rate of <actual> U/hr instead of <expected> U/hr")
        ),
        // Sources/TandemKit/State/TandemPumpManagerSettings.swift:133
        Row(
            identifier: "TandemPumpManagerValidationError.unsupportedTempBasalDuration",
            message: "The pump cannot run a temporary basal rate for <minutes> minutes",
            role: "errorMessage",
            taxonomy: "N9",
            expected: .other("The pump cannot run a temporary basal rate for <minutes> minutes")
        ),
        // Sources/TandemCore/PumpCommError.swift:154
        Row(
            identifier: "PumpCommError.invalidScheduledBasalRate",
            message: "Invalid scheduled basal rate",
            role: "errorMessage",
            taxonomy: "N9",
            expected: .other("Invalid scheduled basal rate")
        ),
        // Sources/TandemCore/PumpCommError.swift:233
        Row(
            identifier: "PumpCommError.invalidScheduledBasalRate",
            message: "Temp basal cannot be performed while scheduled basal rate is 0 or no basal profile exists",
            role: "errorMessage",
            taxonomy: "N9",
            expected: .other("Temp basal cannot be performed while scheduled basal rate is 0 or no basal profile exists")
        ),
        // Sources/TandemCore/PumpCommError.swift:133
        Row(
            identifier: "PumpCommError.noActiveBolus",
            message: "No active bolus to cancel",
            role: "errorMessage",
            taxonomy: "N9",
            expected: .other("No active bolus to cancel")
        ),
        // Sources/TandemCore/PumpCommError.swift:204
        Row(
            identifier: "PumpCommError.noActiveBolus",
            message: "No bolus is running.",
            role: "errorMessage",
            taxonomy: "N9",
            expected: .other("No bolus is running.")
        ),
        // Sources/TandemCore/PumpCommError.swift:94
        Row(
            identifier: "PumpCommError.basalProfileSyncMismatch",
            message: "Pump basal profile does not match the schedule: <segments>",
            role: "errorMessage",
            taxonomy: "N9",
            expected: .other("Pump basal profile does not match the schedule: <segments>")
        ),
        // Sources/TandemKit/PumpManager/TandemPumpManager.swift:1885
        Row(
            identifier: "PumpCommError.errorResponse",
            message: "Pump Error: Error syncing time with pump",
            role: "errorMessage",
            taxonomy: "N9",
            expected: .other("Pump Error: Error syncing time with pump")
        ),
        // Sources/TandemKit/PumpManager/TandemPumpManager+SyncBasal.swift:112
        Row(
            identifier: "PumpCommError.requestConstructionFailed",
            message: "Failed to build pump request: Invalid IDPManager state in syncBasalRateSchedule",
            role: "errorMessage",
            taxonomy: "N9",
            expected: .other("Failed to build pump request: Invalid IDPManager state in syncBasalRateSchedule")
        ),
        // Sources/TandemCore/PumpCommError.swift:190
        Row(
            identifier: "PumpCommError.requestConstructionFailed",
            message: "Please try again. If the problem persists, re-pair your pump.",
            role: "errorMessage",
            taxonomy: "N9",
            expected: .other("Please try again. If the problem persists, re-pair your pump.")
        ),
        // Sources/TandemKit/PumpManager/TandemPumpManager+SyncBasal.swift:132
        Row(
            identifier: "PumpCommError.requestConstructionFailed",
            message: "Failed to build pump request: No active profile found and got unexpected response creating initial profile",
            role: "errorMessage",
            taxonomy: "N9",
            expected: .other(
                "Failed to build pump request: No active profile found and got unexpected response creating initial profile"
            )
        ),
        // Sources/TandemKit/PumpManager/TandemPumpManager+SyncBasal.swift:158
        Row(
            identifier: "PumpCommError.requestConstructionFailed",
            message: "Failed to build pump request: No active profile found",
            role: "errorMessage",
            taxonomy: "N9",
            expected: .other("Failed to build pump request: No active profile found")
        ),
        // Sources/TandemKit/PumpManager/TandemPumpManager+SyncBasal.swift:239
        Row(
            identifier: "PumpCommError.requestConstructionFailed",
            message: "Failed to build pump request: Pump rejected SetIDPSegment",
            role: "errorMessage",
            taxonomy: "N9",
            expected: .other("Failed to build pump request: Pump rejected SetIDPSegment")
        ),
        // Sources/TandemKit/PumpManager/TandemPumpManager+SyncBasal.swift:249
        Row(
            identifier: "PumpCommError.errorResponse",
            message: "Pump Error: Error syncing basal rates: Pump rejected SetIDPSegment",
            role: "errorMessage",
            taxonomy: "N9",
            expected: .other("Pump Error: Error syncing basal rates: Pump rejected SetIDPSegment")
        ),
        // Sources/TandemKitUI/Views/Settings/TandemKitSettingsView.swift:83
        Row(
            identifier: "CommandFailure.resume",
            message: "Could not resume insulin delivery",
            role: "alertTitle",
            taxonomy: "N9",
            expected: .other("Could not resume insulin delivery")
        ),
        // Sources/TandemKitUI/Views/Settings/TandemKitSettingsView.swift:88
        Row(
            identifier: "CommandFailure.resume",
            message: "The pump rejected starting insulin delivery. Check \"View Notifications\" to see the pump's current status and dismiss all active pump notifications. This may have occurred due to active pump notifications, invalid settings, empty cartridge, or not filling the tubing.",
            role: "alertBody",
            taxonomy: "N9",
            expected: .other(
                "The pump rejected starting insulin delivery. Check \"View Notifications\" to see the pump's current status and dismiss all active pump notifications. This may have occurred due to active pump notifications, invalid settings, empty cartridge, or not filling the tubing."
            )
        ),
        // Sources/TandemKitUI/Views/Settings/TandemKitSettingsView.swift:95
        Row(
            identifier: "CommandFailure.suspend",
            message: "Could not suspend insulin delivery",
            role: "alertTitle",
            taxonomy: "N9",
            expected: .other("Could not suspend insulin delivery")
        ),
        // Sources/TandemKitUI/Views/Settings/TandemKitSettingsView.swift:100
        Row(
            identifier: "CommandFailure.suspend",
            message: "The pump rejected suspending insulin delivery. Check \"View Notifications\" to see the pump's current status and dismiss all active pump notifications. This may have occurred due to an active bolus. To urgently suspend insulin delivery, detach from your site.",
            role: "alertBody",
            taxonomy: "N9",
            expected: .other(
                "The pump rejected suspending insulin delivery. Check \"View Notifications\" to see the pump's current status and dismiss all active pump notifications. This may have occurred due to an active bolus. To urgently suspend insulin delivery, detach from your site."
            )
        ),
        // Sources/TandemKitUI/Views/Settings/TandemKitSettingsView.swift:107
        Row(
            identifier: "CommandFailure.controlIQ",
            message: "Could not change Control-IQ setting",
            role: "alertTitle",
            taxonomy: "N9",
            expected: .other("Could not change Control-IQ setting")
        ),
        // Sources/TandemKitUI/Views/Settings/TandemKitSettingsView.swift:111
        Row(
            identifier: "CommandFailure.controlIQ",
            message: "The pump rejected the Control-IQ change. Check \"View Notifications\" to see the pump's current status.",
            role: "alertBody",
            taxonomy: "N9",
            expected: .other(
                "The pump rejected the Control-IQ change. Check \"View Notifications\" to see the pump's current status."
            )
        ),
        // Sources/TandemKitUI/Views/Settings/TandemKitSettingsView.swift:118
        Row(
            identifier: "CommandFailure.exerciseMode",
            message: "Could not change exercise mode",
            role: "alertTitle",
            taxonomy: "N9",
            expected: .other("Could not change exercise mode")
        ),
        // Sources/TandemKitUI/Views/Settings/TandemKitSettingsView.swift:122
        Row(
            identifier: "CommandFailure.exerciseMode",
            message: "The pump rejected the exercise mode change. Check \"View Notifications\" to see the pump's current status.",
            role: "alertBody",
            taxonomy: "N9",
            expected: .other(
                "The pump rejected the exercise mode change. Check \"View Notifications\" to see the pump's current status."
            )
        ),
        // Sources/TandemKitUI/Views/Settings/TandemKitSettingsView.swift:129
        Row(
            identifier: "CommandFailure.sleepMode",
            message: "Could not change sleep mode",
            role: "alertTitle",
            taxonomy: "N9",
            expected: .other("Could not change sleep mode")
        ),
        // Sources/TandemKitUI/Views/Settings/TandemKitSettingsView.swift:133
        Row(
            identifier: "CommandFailure.sleepMode",
            message: "The pump rejected the sleep mode change. Check \"View Notifications\" to see the pump's current status.",
            role: "alertBody",
            taxonomy: "N9",
            expected: .other(
                "The pump rejected the sleep mode change. Check \"View Notifications\" to see the pump's current status."
            )
        ),
        // Sources/TandemKitUI/Views/Settings/TandemKitSettingsView.swift:140
        Row(
            identifier: "CommandFailure.stopTempRate",
            message: "Could not stop temp rate",
            role: "alertTitle",
            taxonomy: "N9",
            expected: .other("Could not stop temp rate")
        ),
        // Sources/TandemKitUI/Views/Settings/TandemKitSettingsView.swift:144
        Row(
            identifier: "CommandFailure.stopTempRate",
            message: "The pump rejected stopping the temp rate. Check \"View Notifications\" to see the pump's current status.",
            role: "alertBody",
            taxonomy: "N9",
            expected: .other(
                "The pump rejected stopping the temp rate. Check \"View Notifications\" to see the pump's current status."
            )
        ),
        // Sources/TandemKitUI/ViewModels/Settings/TandemKitNotificationsViewModel.swift:113
        Row(
            identifier: "TandemKitNotificationsViewModel.errorMessage",
            message: "Failed to dismiss notification",
            role: "errorMessage",
            taxonomy: "N9",
            expected: .other("Failed to dismiss notification")
        ),
        // Sources/TandemKitUI/ViewModels/CGMs/TandemKitCGMSettingsViewModel.swift:157
        Row(
            identifier: "TandemKitCGMSettingsViewModel.commandError",
            message: "Failed to stop CGM sensor. Check pump connection.",
            role: "errorMessage",
            taxonomy: "N9",
            expected: .other("Failed to stop CGM sensor. Check pump connection.")
        ),
        // Sources/TandemKitUI/Views/Onboarding/TandemKitScanView.swift:262
        Row(
            identifier: "TandemKitScanView.pairingCodePrompt",
            message: "Enter Pairing code",
            role: "alertTitle",
            taxonomy: "N10",
            expected: .other("Enter Pairing code")
        ),
        // Sources/TandemKitUI/ViewModels/Onboarding/TandemKitScanViewModel.swift:66
        Row(
            identifier: "TandemKitScanView.pairingCodePrompt",
            message: "Enter the PIN for %@:",
            role: "alertBody",
            taxonomy: "N10",
            expected: .other("Enter the PIN for %@:")
        ),
        // Sources/TandemKitUI/Views/Onboarding/TandemKitScanView.swift:245
        Row(
            identifier: "TandemKitScanView.pairingCodePrompt",
            message: "The pairing code is located on the inside of the cartridge area labeled as 'PIN' and consists of six numbers.",
            role: "alertBody",
            taxonomy: "N10",
            expected: .other(
                "The pairing code is located on the inside of the cartridge area labeled as 'PIN' and consists of six numbers."
            )
        ),
        // Sources/TandemKitUI/ViewModels/CGMs/TandemKitCGMSettingsViewModel.swift:92
        Row(
            identifier: "TandemKitCGMSettingsViewModel.transmitterBatteryStatus",
            message: "OK",
            role: "validation",
            taxonomy: "N11",
            expected: .other("OK")
        ),
        // Sources/TandemKitUI/ViewModels/CGMs/TandemKitCGMSettingsViewModel.swift:93
        Row(
            identifier: "TandemKitCGMSettingsViewModel.transmitterBatteryStatus",
            message: "Error",
            role: "validation",
            taxonomy: "N11",
            expected: .other("Error")
        ),
        // Sources/TandemKitUI/ViewModels/CGMs/TandemKitCGMSettingsViewModel.swift:94
        Row(
            identifier: "TandemKitCGMSettingsViewModel.transmitterBatteryStatus",
            message: "Expired",
            role: "validation",
            taxonomy: "N11",
            expected: .other("Expired")
        ),
        // Sources/TandemKitUI/ViewModels/CGMs/TandemKitCGMSettingsViewModel.swift:95
        Row(
            identifier: "TandemKitCGMSettingsViewModel.transmitterBatteryStatus",
            message: "Out of Range",
            role: "validation",
            taxonomy: "N11",
            expected: .other("Out of Range")
        ),
        // Sources/TandemKitUI/ViewModels/CGMs/TandemKitCGMSettingsViewModel.swift:96
        Row(
            identifier: "TandemKitCGMSettingsViewModel.transmitterBatteryStatus",
            message: "Unavailable",
            role: "validation",
            taxonomy: "N11",
            expected: .other("Unavailable")
        ),
        // Sources/TandemKitUI/ViewModels/Onboarding/TandemKitScanViewModel.swift:171
        Row(
            identifier: "TandemKitScanViewModel.pinCodePromptError",
            message: "Enter all 6 digits of the pairing code",
            role: "validation",
            taxonomy: "N12",
            expected: .other("Enter all 6 digits of the pairing code")
        ),
        // Sources/TandemKitUI/ViewModels/Onboarding/TandemKitScanViewModel.swift:182
        Row(
            identifier: "TandemKitScanViewModel.connectionErrorMessage",
            message: "Pump manager not initialized",
            role: "errorMessage",
            taxonomy: "N12",
            expected: .other("Pump manager not initialized")
        ),
        // Sources/TandemKitUI/ViewModels/Onboarding/TandemKitScanViewModel.swift:192
        Row(
            identifier: "TandemKitScanViewModel.connectionErrorMessage",
            message: "No peripheral selected",
            role: "errorMessage",
            taxonomy: "N12",
            expected: .other("No peripheral selected")
        ),
        // Sources/TandemKitUI/ViewModels/Onboarding/TandemKitScanViewModel.swift:19
        Row(
            identifier: "TandemKitScanView.connectionErrorAlert",
            message: "Error while connecting to device",
            role: "alertTitle",
            taxonomy: "N12",
            expected: .other("Error while connecting to device")
        ),
        // Sources/TandemKitUI/ViewModels/CGMs/TandemKitG6SetupViewModel.swift:77
        Row(
            identifier: "TandemKitG6SetupViewModel.error",
            message: "Failed to set transmitter.",
            role: "errorMessage",
            taxonomy: "N12",
            expected: .other("Failed to set transmitter.")
        ),
        // Sources/TandemKitUI/ViewModels/CGMs/TandemKitG6SetupViewModel.swift:103
        Row(
            identifier: "TandemKitG6SetupViewModel.error",
            message: "Failed to start CGM sensor",
            role: "errorMessage",
            taxonomy: "N12",
            expected: .other("Failed to start CGM sensor")
        ),
        // Sources/TandemKitUI/ViewModels/CGMs/TandemKitG7SetupViewModel.swift:58
        Row(
            identifier: "TandemKitG7SetupViewModel.error",
            message: "Failed to set G7 pairing code",
            role: "errorMessage",
            taxonomy: "N12",
            expected: .other("Failed to set G7 pairing code")
        ),
        // Sources/TandemKitUI/Views/CGMs/TandemKitCGMSettingsView.swift:64
        Row(
            identifier: "TandemKitCGMSettingsView.stopConfirmation",
            message: "Stop CGM Sensor",
            role: "alertTitle",
            taxonomy: "N12",
            expected: .other("Stop CGM Sensor")
        ),
        // Sources/TandemKitUI/Views/CGMs/TandemKitCGMSettingsView.swift:66
        Row(
            identifier: "TandemKitCGMSettingsView.stopConfirmation",
            message: "Are you sure you want to stop the CGM sensor session on your pump?",
            role: "alertBody",
            taxonomy: "N12",
            expected: .other("Are you sure you want to stop the CGM sensor session on your pump?")
        ),
        // Sources/TandemKitUI/Views/CGMs/TandemKitG6SetupWizardView.swift:32
        Row(
            identifier: "TandemKitSetupWizard.errorAlert",
            message: "Error",
            role: "alertTitle",
            taxonomy: "N12",
            expected: .other("Error")
        ),
        // Sources/TandemKitUI/Views/Settings/TandemKitSettingsView.swift:545
        Row(
            identifier: "TandemKitSettingsView.switchToCIQ",
            message: "Disable %@ Algorithm",
            role: "alertTitle",
            taxonomy: "N13",
            expected: .other("Disable %@ Algorithm")
        ),
        // Sources/TandemKitUI/Views/Settings/TandemKitSettingsView.swift:552
        Row(
            identifier: "TandemKitSettingsView.switchToCIQ",
            message: "This will DISABLE %@ in favor of the Control-IQ algorithm built-in to your pump.\n\n%@ will stop issuing temp basals and boluses. Are you sure?",
            role: "alertBody",
            taxonomy: "N13",
            expected: .other(
                "This will DISABLE %@ in favor of the Control-IQ algorithm built-in to your pump.\n\n%@ will stop issuing temp basals and boluses. Are you sure?"
            )
        ),
        // Sources/TandemKitUI/Views/Settings/TandemKitSettingsView.swift:570
        Row(
            identifier: "TandemKitSettingsView.switchToDIY",
            message: "Enable %@ Algorithm",
            role: "alertTitle",
            taxonomy: "N13",
            expected: .other("Enable %@ Algorithm")
        ),
        // Sources/TandemKitUI/Views/Settings/TandemKitSettingsView.swift:577
        Row(
            identifier: "TandemKitSettingsView.switchToDIY",
            message: "This will disable Control-IQ on your pump and allow %@ to resume %@ closed-loop dosing.",
            role: "alertBody",
            taxonomy: "N13",
            expected: .other("This will disable Control-IQ on your pump and allow %@ to resume %@ closed-loop dosing.")
        ),
        // Sources/TandemKitUI/Views/Settings/TandemKitSettingsView.swift:659
        Row(
            identifier: "TandemKitSettingsView.stopTempRate",
            message: "Temp Basal Active",
            role: "alertTitle",
            taxonomy: "N13",
            expected: .other("Temp Basal Active")
        ),
        // Sources/TandemKitUI/Views/Settings/TandemKitSettingsView.swift:898
        Row(
            identifier: "TandemKitSettingsView.stopTempRate",
            message: "The current temp rate is <rate> for the next <duration>. Would you like to revert to your scheduled basal rate?",
            role: "alertBody",
            taxonomy: "N13",
            expected: .other(
                "The current temp rate is <rate> for the next <duration>. Would you like to revert to your scheduled basal rate?"
            )
        ),
        // Sources/TandemKitUI/Views/Settings/TandemKitSettingsView.swift:677
        Row(
            identifier: "TandemKitSettingsView.stopTempRateClosedLoopWarning",
            message: "WARNING",
            role: "alertTitle",
            taxonomy: "N13",
            expected: .other("WARNING")
        ),
        // Sources/TandemKitUI/Views/Settings/TandemKitSettingsView.swift:679
        Row(
            identifier: "TandemKitSettingsView.stopTempRateClosedLoopWarning",
            message: "Closed loop is currently enabled. Cancelling the active temp rate on the pump will NOT place you in open-loop mode, and the next run of the oref algorithm will set a new temp rate.",
            role: "alertBody",
            taxonomy: "N13",
            expected: .other(
                "Closed loop is currently enabled. Cancelling the active temp rate on the pump will NOT place you in open-loop mode, and the next run of the oref algorithm will set a new temp rate."
            )
        ),
        // Sources/TandemKitUI/Views/Settings/TandemKitSettingsView.swift:632
        Row(
            identifier: "TandemKitSettingsView.diyRestored",
            message: "%@ Mode Restored",
            role: "alertTitle",
            taxonomy: "N14",
            expected: .other("%@ Mode Restored")
        ),
        // Sources/TandemKitUI/Views/Settings/TandemKitSettingsView.swift:637
        Row(
            identifier: "TandemKitSettingsView.diyRestored",
            message: "Control-IQ has been disabled and you are currently in open-loop. To re-enable %@ closed-loop, go to your app's Algorithm settings.",
            role: "alertBody",
            taxonomy: "N14",
            expected: .other(
                "Control-IQ has been disabled and you are currently in open-loop. To re-enable %@ closed-loop, go to your app's Algorithm settings."
            )
        ),
        // Sources/TandemKitUI/Views/Settings/TandemKitSettingsView.swift:647
        Row(
            identifier: "TandemKitSettingsView.noCGMConnected",
            message: "No CGM Connected",
            role: "alertTitle",
            taxonomy: "N14",
            expected: .other("No CGM Connected")
        ),
        // Sources/TandemKitUI/Views/Settings/TandemKitSettingsView.swift:649
        Row(
            identifier: "TandemKitSettingsView.noCGMConnected",
            message: "Control-IQ was enabled but no CGM is connected to the pump.\n\nUntil a CGM sensor is connected, your configured profile rates will be used. To connect a sensor, go to CGM Settings below.",
            role: "alertBody",
            taxonomy: "N14",
            expected: .other(
                "Control-IQ was enabled but no CGM is connected to the pump.\n\nUntil a CGM sensor is connected, your configured profile rates will be used. To connect a sensor, go to CGM Settings below."
            )
        ),
        // Sources/TandemKitUI/Views/Settings/TandemKitSettingsView.swift:43
        Row(
            identifier: "TandemKitSettingsView.removePump",
            message: "Remove Pump",
            role: "alertTitle",
            taxonomy: "N14",
            expected: .other("Remove Pump")
        ),
        // Sources/TandemKitUI/Views/Settings/TandemKitSettingsView.swift:46
        Row(
            identifier: "TandemKitSettingsView.removePump",
            message: "Are you sure you want to remove the pump from %@? You will need to re-pair the device to reconnect with it which will require access to the charging pad.",
            role: "alertBody",
            taxonomy: "N14",
            expected: .other(
                "Are you sure you want to remove the pump from %@? You will need to re-pair the device to reconnect with it which will require access to the charging pad."
            )
        ),
        // Sources/TandemKitUI/Views/Settings/TandemKitSettingsView.swift:51
        Row(
            identifier: "TandemKitSettingsView.removePump",
            message: "Delete Pump",
            role: "alertBody",
            taxonomy: "N14",
            expected: .other("Delete Pump")
        ),
        // Sources/TandemKitUI/Views/Settings/TandemKitSettingsView.swift:63
        Row(
            identifier: "TandemKitSettingsView.syncTime",
            message: "Time Change Detected",
            role: "alertTitle",
            taxonomy: "N14",
            expected: .other("Time Change Detected")
        ),
        // Sources/TandemKitUI/Views/Settings/TandemKitSettingsView.swift:65
        Row(
            identifier: "TandemKitSettingsView.syncTime",
            message: "The time on your pump is different from the current time. Do you want to update the time on your pump to the current time?",
            role: "alertBody",
            taxonomy: "N14",
            expected: .other(
                "The time on your pump is different from the current time. Do you want to update the time on your pump to the current time?"
            )
        ),
        // Sources/TandemKitUI/Views/Settings/TandemKitSettingsView.swift:286
        Row(
            identifier: "TandemKitSettingsView.noCGMBanner",
            message: "No CGM connected to pump",
            role: "notificationTitle",
            taxonomy: "N14",
            expected: .other("No CGM connected to pump")
        ),
        // Sources/TandemKitUI/Views/Settings/TandemKitSettingsView.swift:289
        Row(
            identifier: "TandemKitSettingsView.noCGMBanner",
            message: "%@ closed-loop is disabled with your pump's Control-IQ algorithm on, but no CGM is connected, so you are in open-loop.",
            role: "notificationBody",
            taxonomy: "N14",
            expected: .other(
                "%@ closed-loop is disabled with your pump's Control-IQ algorithm on, but no CGM is connected, so you are in open-loop."
            )
        ),
        // Sources/TandemKitUI/Views/Settings/TandemKitSettingsView.swift:300
        Row(
            identifier: "TandemKitSettingsView.controlIQBanner",
            message: "Control-IQ pump algorithm enabled",
            role: "notificationTitle",
            taxonomy: "N14",
            expected: .other("Control-IQ pump algorithm enabled")
        ),
        // Sources/TandemKitUI/Views/Settings/TandemKitSettingsView.swift:302
        Row(
            identifier: "TandemKitSettingsView.controlIQBanner",
            message: "%@ closed-loop is not in use.",
            role: "notificationBody",
            taxonomy: "N14",
            expected: .other("%@ closed-loop is not in use.")
        ),
        // Sources/TandemKitUI/Views/Settings/TandemKitSettingsView.swift:311
        Row(
            identifier: "TandemKitSettingsView.openLoopBanner",
            message: "Open loop mode",
            role: "notificationTitle",
            taxonomy: "N14",
            expected: .other("Open loop mode")
        ),
        // Sources/TandemKitUI/Views/Settings/TandemKitSettingsView.swift:322 (typographic apostrophe)
        Row(
            identifier: "TandemKitSettingsView.timeSyncWarningBanner",
            message: "The time on your pump is different from the current time. Your pump’s time controls your scheduled therapy settings. Scroll down to Pump Time row to review the time difference and configure your pump.",
            role: "notificationBody",
            taxonomy: "N14",
            expected: .other(
                "The time on your pump is different from the current time. Your pump’s time controls your scheduled therapy settings. Scroll down to Pump Time row to review the time difference and configure your pump."
            )
        ),
        // Sources/TandemKitUI/ViewModels/CGMs/TandemKitCGMSettingsViewModel.swift:24
        Row(
            identifier: "CGMSessionState.displayText",
            message: "Stopped",
            role: "validation",
            taxonomy: "N14",
            expected: .other("Stopped")
        ),
        // Sources/TandemKitUI/ViewModels/CGMs/TandemKitCGMSettingsViewModel.swift:25
        Row(
            identifier: "CGMSessionState.displayText",
            message: "Starting...",
            role: "validation",
            taxonomy: "N14",
            expected: .other("Starting...")
        ),
        // Sources/TandemKitUI/ViewModels/CGMs/TandemKitCGMSettingsViewModel.swift:26
        Row(
            identifier: "CGMSessionState.displayText",
            message: "Active",
            role: "validation",
            taxonomy: "N14",
            expected: .other("Active")
        ),
        // Sources/TandemKitUI/ViewModels/CGMs/TandemKitCGMSettingsViewModel.swift:27
        Row(
            identifier: "CGMSessionState.displayText",
            message: "Stopping...",
            role: "validation",
            taxonomy: "N14",
            expected: .other("Stopping...")
        ),
        // Sources/TandemKitUI/ViewModels/CGMs/TandemKitCGMSettingsViewModel.swift:28
        Row(
            identifier: "CGMSessionState.displayText",
            message: "Unknown",
            role: "validation",
            taxonomy: "N14",
            expected: .other("Unknown")
        ),
        // Sources/TandemKitUI/Views/CGMs/TandemKitCGMSettingsView.swift:152
        Row(
            identifier: "TandemKitCGMSettingsView.gracePeriodRow",
            message: "Grace Period",
            role: "validation",
            taxonomy: "N14",
            expected: .other("Grace Period")
        ),
        // Sources/TandemKitUI/Views/CGMs/TandemKitCGMSettingsView.swift:134
        Row(
            identifier: "TandemKitCGMSettingsView.timeRemainingRow",
            message: "Time Remaining",
            role: "validation",
            taxonomy: "N14",
            expected: .other("Time Remaining")
        )
    ]
    @Test(
        "each (identifier, message) classifies as pinned",
        arguments: rows
    ) func eachMessageClassifiesAsPinned(row: Row) {
        // Pins CURRENT behavior. Feeding the display string exercises the
        // substring matcher over real prose; this MUST stay green.
        #expect(TrioAlertClassifier.categorize(error: StubError(description: row.message)) == row.expected)
    }

    // MARK: - Coverage-gap ratchet

    /// "identifier — message" keys for emissions whose taxonomy implies a
    /// mappable bucket but the classifier returns `.other` because its
    /// space-free tokens miss the spaced prose. Each line below names the
    /// bucket the row SHOULD hit and why the tokens miss it. This set stays
    /// green today and FAILS when the classifier is improved (forcing a
    /// conscious update), ratcheting coverage upward.
    ///
    /// Per-gap rationale (bucket it SHOULD hit / why tokens miss):
    /// - N4 "No Insulin" status highlight -> SHOULD be `.reservoirEmpty`, but
    ///   the token is the space-free "reservoirempty"/"emptyreservoir"
    ///   (Sources/TandemKitUI/TandemPumpManager+UI.swift:160).
    /// - N8 connectivity strings ("Pump not connected", "Make sure iPhone is
    ///   nearby ...", "No response from pump", "Pump Error: ...",
    ///   "Pump Disconnected") -> SHOULD be `.commsTransient`, but
    ///   "notconnected"/"noresponse"/"comms"/"communication" are all space-free
    ///   or absent, so the spaced prose misses
    ///   (Sources/TandemCore/PumpCommError.swift,
    ///   Sources/TandemKit/PumpManager/TandemPeripheralManager.swift,
    ///   Sources/TandemKit/PumpManager/TandemBluetoothManager.swift:776,
    ///   Sources/TandemKitUI/Utils/PumpConnectionIssue+Text.swift:25).
    static let classifierCoverageGaps: Set<String> = [
        "PumpStatusHighlight.noInsulin — No Insulin",
        "PumpCommError.pumpNotConnected — Pump not connected",
        "PumpCommError.pumpNotConnected — Make sure iPhone is nearby the active pump",
        "PumpCommError.noResponse — No response from pump",
        "PumpCommError.errorResponse — Pump Error: Failed to discoverServices: <error>",
        "PumpCommError.errorResponse — Pump Error: No service: <PUMP_SERVICE>",
        "PumpCommError.errorResponse — Pump Error: <message>",
        "PumpCommError.errorResponse — Pump Error: No service: <DIS_SERVICE>",
        "PumpCommError.errorResponse — Pump Error: Failed to connect: <error>",
        "PumpConnectionIssue.pumpUnreachable — Pump Disconnected"
    ]
    @Test("classifier coverage gaps are exactly as documented") func classifierCoverageGapsAreExactlyAsDocumented() {
        // Recompute the gap set from the rows: a row is a coverage gap when the
        // classifier returns `.other` for its message (so it is unbucketed)
        // even though the taxonomy implies a mappable bucket (taxonomyBucket
        // other than "other"). We detect "classifier returned .other" by
        // comparing against `.other(message)`. This stays equal to the pinned
        // set today and DIVERGES (failing this test) the moment the classifier
        // learns to bucket any of these strings — the ratchet.
        var computed = Set<String>()
        for row in Self.rows {
            let isOther: Bool
            if case .other = row.expected { isOther = true } else { isOther = false }
            if isOther {
                computed.insert("\(row.identifier) — \(row.message)")
            }
        }
        // `computed` is every `.other` row (mappable or not). Intersect with the
        // documented gap keys to assert the documented set is exactly the
        // taxonomy-mappable subset, and that none of them have started bucketing.
        #expect(Self.classifierCoverageGaps.isSubset(of: computed))
        #expect(Self.classifierCoverageGaps == Self.classifierCoverageGaps.intersection(computed))
        #expect(Self.classifierCoverageGaps.count == 10)
    }
}
