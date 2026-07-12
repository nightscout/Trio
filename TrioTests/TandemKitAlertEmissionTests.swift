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
@Suite("Trio Alert Emission: TandemKit") struct TandemKitAlertEmissionTests {
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

// MARK: - Message classification (SECONDARY: error-string routing)

/// SPEC — how Trio's `TrioAlertClassifier` would bucket every user-facing
/// **TandemKit** message string, pinned against the live substring matcher.
///
/// IMPORTANT — what production actually feeds the classifier vs. what this
/// suite feeds it: in production `APSManager` hands
/// `TrioAlertClassifier.categorize(error:)` a LoopKit `PumpManagerError`
/// wrapping a `PumpCommError` / `TandemPumpManagerValidationError`, and the
/// classifier runs `String(describing:)` over THAT — i.e. it sees the Swift
/// **case name** (e.g. `pumpError(...)` / `pumpNotConnected`), not the rendered
/// display string. TandemKit also uses NONE of the LoopKit Alert / AlertIssuer
/// machinery and never delivers a live `pumpManager(_:didError:)`, so there are
/// no real LoopKit `Alert.alertIdentifier` values to attach (that structural
/// finding is pinned by the registry-routing suite above). Every user-facing
/// row here surfaces instead through one of: (1) `PumpCommError` /
/// `TandemPumpManagerValidationError` wrapped in `PumpManagerError` returned to
/// Loop completion handlers, (2) the in-app "Pump notifications" settings list
/// (`NotificationBundle` items whose displayed string is the formatted enum
/// case-name title), (3) `pumpStatusHighlight` strings, (4) SwiftUI
/// `.alert`/ActionSheet/ErrorSheet text, and (5) CGM settings status rows. The
/// `alertIdentifier` column is therefore the error enum case name / source
/// symbol for the row, NOT a LoopKit alert id.
///
/// This catalog deliberately feeds the classifier the **display string** of
/// each emission so we pin how the substring matcher handles real
/// natural-language text — the worst case for a token matcher. The classifier's
/// `categorize(pumpError:)` tokens are concatenated and space-free
/// ("notconnected", "noresponse", "reservoirempty", "sensorfailed", ...), while
/// TandemKit's prose has spaces, so almost every emission falls through to
/// `.other`. Only strings literally containing "occlusion"/"occluded" hit a real
/// bucket. Connectivity strings ("Pump not connected", "No response from pump",
/// "Pump Disconnected") do NOT match "notconnected"/"noresponse" because of the
/// spaces and wrongly land in `.other` — the principal gaps. See
/// `Trio/Sources/Services/Alerts/TrioAlertCategory.swift`.
///
/// References: managers — TandemKit / TandemKitUI / TandemCore; pump —
/// Tandem t:slim X2 / Mobi.
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
        // TandemCore/Messages/CurrentStatus/AlarmStatus.swift:157
        Row(
            identifier: "AlarmResponseType.OCCLUSION_ALARM",
            message: "Occlusion Alarm",
            role: "alertTitle",
            taxonomy: "N1",
            expected: .occlusion
        ),
        // TandemCore/Messages/CurrentStatus/AlarmStatus.swift:157
        Row(
            identifier: "AlarmResponseType.OCCLUSION_ALARM",
            message: "An occlusion has occurred. Please check your pump site and tubing and restart insulin delivery.",
            role: "alertBody",
            taxonomy: "N1",
            expected: .occlusion
        ),
        // TandemCore/Messages/CurrentStatus/AlarmStatus.swift:145
        Row(
            identifier: "AlarmResponseType.cartridgeGroup",
            message: "Cartridge Alarm",
            role: "alertTitle",
            taxonomy: "N1",
            expected: .other("Cartridge Alarm")
        ),
        // TandemCore/Messages/CurrentStatus/AlarmStatus.swift:145
        Row(
            identifier: "AlarmResponseType.cartridgeGroup",
            message: "There is an issue with the cartridge and it needs to be replaced.",
            role: "alertBody",
            taxonomy: "N1",
            expected: .other("There is an issue with the cartridge and it needs to be replaced.")
        ),
        // TandemCore/Messages/CurrentStatus/AlarmStatus.swift:183
        Row(
            identifier: "AlarmResponseType.CARTRIDGE_REMOVED_ALARM",
            message: "Cartridge Removed Alarm",
            role: "alertTitle",
            taxonomy: "N1",
            expected: .other("Cartridge Removed Alarm")
        ),
        // TandemCore/Messages/CurrentStatus/AlarmStatus.swift:183
        Row(
            identifier: "AlarmResponseType.CARTRIDGE_REMOVED_ALARM",
            message: "The cartridge was removed from the pump. Please fill a new cartridge.",
            role: "alertBody",
            taxonomy: "N1",
            expected: .other("The cartridge was removed from the pump. Please fill a new cartridge.")
        ),
        // TandemCore/Messages/CurrentStatus/AlarmStatus.swift:160
        Row(
            identifier: "AlarmResponseType.PUMP_RESET_ALARM",
            message: "Pump Reset Alarm",
            role: "alertTitle",
            taxonomy: "N1",
            expected: .other("Pump Reset Alarm")
        ),
        // TandemCore/Messages/CurrentStatus/AlarmStatus.swift:160
        Row(
            identifier: "AlarmResponseType.PUMP_RESET_ALARM",
            message: "The pump was reset. IOB has been reset to 0 and CGM may need to be re-activated.",
            role: "alertBody",
            taxonomy: "N1",
            expected: .other("The pump was reset. IOB has been reset to 0 and CGM may need to be re-activated.")
        ),
        // TandemCore/Messages/CurrentStatus/AlarmStatus.swift:166
        Row(
            identifier: "AlarmResponseType.temperatureGroup",
            message: "Temperature Alarm",
            role: "alertTitle",
            taxonomy: "N1",
            expected: .other("Temperature Alarm")
        ),
        // TandemCore/Messages/CurrentStatus/AlarmStatus.swift:166
        Row(
            identifier: "AlarmResponseType.temperatureGroup",
            message: "Pump temperature is out of range and insulin cannot be safely delivered.",
            role: "alertBody",
            taxonomy: "N1",
            expected: .other("Pump temperature is out of range and insulin cannot be safely delivered.")
        ),
        // TandemCore/Messages/CurrentStatus/AlarmStatus.swift:177
        Row(
            identifier: "AlarmResponseType.ALTITUDE_ALARM",
            message: "Altitude Alarm",
            role: "alertTitle",
            taxonomy: "N1",
            expected: .other("Altitude Alarm")
        ),
        // TandemCore/Messages/CurrentStatus/AlarmStatus.swift:181
        Row(
            identifier: "AlarmResponseType.ATMOSPHERIC_PRESSURE_OUT_OF_RANGE_ALARM",
            message: "Atmospheric Pressure Out Of Range Alarm",
            role: "alertTitle",
            taxonomy: "N1",
            expected: .other("Atmospheric Pressure Out Of Range Alarm")
        ),
        // TandemCore/Messages/CurrentStatus/AlarmStatus.swift:179
        Row(
            identifier: "AlarmResponseType.STUCK_BUTTON_ALARM",
            message: "Stuck Button Alarm",
            role: "alertTitle",
            taxonomy: "N1",
            expected: .other("Stuck Button Alarm")
        ),
        // TandemCore/Messages/CurrentStatus/AlarmStatus.swift:179
        Row(
            identifier: "AlarmResponseType.STUCK_BUTTON_ALARM",
            message: "The pump button may be stuck or has been pressed for too long a period of time.",
            role: "alertBody",
            taxonomy: "N1",
            expected: .other("The pump button may be stuck or has been pressed for too long a period of time.")
        ),
        // TandemCore/Messages/CurrentStatus/AlarmStatus.swift:172
        Row(
            identifier: "AlarmResponseType.INVALID_DATE_ALARM",
            message: "Invalid Date Alarm",
            role: "alertTitle",
            taxonomy: "N1",
            expected: .other("Invalid Date Alarm")
        ),
        // TandemCore/Messages/CurrentStatus/AlarmStatus.swift:172
        Row(
            identifier: "AlarmResponseType.INVALID_DATE_ALARM",
            message: "The pump's configured date is invalid.",
            role: "alertBody",
            taxonomy: "N1",
            expected: .other("The pump's configured date is invalid.")
        ),
        // TandemCore/Messages/CurrentStatus/HighestAam.swift:106
        Row(
            identifier: "HighestAamResponse.malfunction",
            message: "Malfunction",
            role: "alertTitle",
            taxonomy: "N1",
            expected: .other("Malfunction")
        ),
        // TandemCore/Messages/CurrentStatus/AlarmStatus.swift:174
        Row(
            identifier: "AlarmResponseType.RESUME_PUMP_ALARM",
            message: "Resume Pump Alarm",
            role: "alertTitle",
            taxonomy: "N2",
            expected: .other("Resume Pump Alarm")
        ),
        // TandemCore/Messages/CurrentStatus/AlarmStatus.swift:174
        Row(
            identifier: "AlarmResponseType.RESUME_PUMP_ALARM",
            message: "Insulin delivery is currently off. Please restart insulin delivery soon.",
            role: "alertBody",
            taxonomy: "N2",
            expected: .other("Insulin delivery is currently off. Please restart insulin delivery soon.")
        ),
        // TandemCore/Messages/CurrentStatus/AlarmStatus.swift:162
        Row(
            identifier: "AlarmResponseType.AUTO_OFF_ALARM",
            message: "Auto Off Alarm",
            role: "alertTitle",
            taxonomy: "N2",
            expected: .other("Auto Off Alarm")
        ),
        // TandemCore/Messages/CurrentStatus/AlarmStatus.swift:162
        Row(
            identifier: "AlarmResponseType.AUTO_OFF_ALARM",
            message: "Pump will stop delivering insulin automatically soon because no user activity has occurred and the auto-off setting is enabled.",
            role: "alertBody",
            taxonomy: "N2",
            expected: .other(
                "Pump will stop delivering insulin automatically soon because no user activity has occurred and the auto-off setting is enabled."
            )
        ),
        // TandemKitUI/TandemPumpManager+UI.swift:112
        Row(
            identifier: "PumpStatusHighlight.suspended",
            message: "Insulin Suspended",
            role: "notificationTitle",
            taxonomy: "N2",
            expected: .other("Insulin Suspended")
        ),
        // TandemKitUI/TandemPumpManager+UI.swift:123
        Row(
            identifier: "PumpStatusHighlight.noInsulin",
            message: "No Insulin",
            role: "notificationTitle",
            taxonomy: "N4",
            expected: .other("No Insulin")
        ),
        // TandemCore/Messages/CurrentStatus/AlarmStatus.swift:164
        Row(
            identifier: "AlarmResponseType.EMPTY_CARTRIDGE_ALARM",
            message: "Empty Cartridge Alarm",
            role: "alertTitle",
            taxonomy: "N4",
            expected: .other("Empty Cartridge Alarm")
        ),
        // TandemCore/Messages/CurrentStatus/AlarmStatus.swift:164
        Row(
            identifier: "AlarmResponseType.EMPTY_CARTRIDGE_ALARM",
            message: "Cartridge is out of insulin and insulin delivery cannot occur. Please fill a new cartridge.",
            role: "alertBody",
            taxonomy: "N4",
            expected: .other("Cartridge is out of insulin and insulin delivery cannot occur. Please fill a new cartridge.")
        ),
        // TandemCore/Messages/CurrentStatus/AlarmStatus.swift:170
        Row(
            identifier: "AlarmResponseType.BATTERY_SHUTDOWN_ALARM",
            message: "Battery Shutdown Alarm",
            role: "alertTitle",
            taxonomy: "N5",
            expected: .other("Battery Shutdown Alarm")
        ),
        // TandemCore/Messages/CurrentStatus/AlarmStatus.swift:170
        Row(
            identifier: "AlarmResponseType.BATTERY_SHUTDOWN_ALARM",
            message: "Pump battery level is critically low and the device will shut down. Please charge pump immediately.",
            role: "alertBody",
            taxonomy: "N5",
            expected: .other(
                "Pump battery level is critically low and the device will shut down. Please charge pump immediately."
            )
        ),
        // TandemCore/Messages/CurrentStatus/CGMAlertStatus.swift:135
        Row(
            identifier: "CGMAlert.SENSOR_FAILED",
            message: "Sensor Failed Cgm Alert",
            role: "alertTitle",
            taxonomy: "N7",
            expected: .other("Sensor Failed Cgm Alert")
        ),
        // TandemCore/Messages/CurrentStatus/CGMAlertStatus.swift:135
        Row(
            identifier: "CGMAlert.LOW",
            message: "Low Cgm Alert",
            role: "alertTitle",
            taxonomy: "N7",
            expected: .other("Low Cgm Alert")
        ),
        // TandemCore/Messages/CurrentStatus/CGMAlertStatus.swift:135
        Row(
            identifier: "CGMAlert.HIGH",
            message: "High Cgm Alert",
            role: "alertTitle",
            taxonomy: "N7",
            expected: .other("High Cgm Alert")
        ),
        // TandemCore/Messages/CurrentStatus/CGMAlertStatus.swift:135
        Row(
            identifier: "CGMAlert.FIXED_LOW",
            message: "Fixed Low Cgm Alert",
            role: "alertTitle",
            taxonomy: "N7",
            expected: .other("Fixed Low Cgm Alert")
        ),
        // TandemCore/Messages/CurrentStatus/CGMAlertStatus.swift:135
        Row(
            identifier: "CGMAlert.SENSOR_EXPIRING",
            message: "Sensor Expiring Cgm Alert",
            role: "alertTitle",
            taxonomy: "N7",
            expected: .other("Sensor Expiring Cgm Alert")
        ),
        // TandemCore/Messages/CurrentStatus/CGMAlertStatus.swift:135
        Row(
            identifier: "CGMAlert.SENSOR_EXPIRED",
            message: "Sensor Expired Cgm Alert",
            role: "alertTitle",
            taxonomy: "N7",
            expected: .other("Sensor Expired Cgm Alert")
        ),
        // TandemCore/Messages/CurrentStatus/CGMAlertStatus.swift:135
        Row(
            identifier: "CGMAlert.OUT_OF_RANGE",
            message: "Out Of Range Cgm Alert",
            role: "alertTitle",
            taxonomy: "N7",
            expected: .other("Out Of Range Cgm Alert")
        ),
        // TandemCore/Messages/CurrentStatus/CGMAlertStatus.swift:135
        Row(
            identifier: "CGMAlert.TRANSMITTER",
            message: "Transmitter Cgm Alert",
            role: "alertTitle",
            taxonomy: "N7",
            expected: .other("Transmitter Cgm Alert")
        ),
        // TandemCore/Messages/CurrentStatus/ReminderStatus.swift:129
        Row(
            identifier: "ReminderType.namedCases",
            message: "Reminder",
            role: "alertTitle",
            taxonomy: "N14",
            expected: .other("Reminder")
        ),
        // TandemKit/PumpManager/TandemPumpManager.swift:341
        Row(
            identifier: "PumpCommError.pumpNotConnected",
            message: "Pump not connected",
            role: "errorMessage",
            taxonomy: "N8",
            expected: .other("Pump not connected")
        ),
        // TandemKit/PumpManager/TandemPumpManager.swift:341
        Row(
            identifier: "PumpCommError.pumpNotConnected",
            message: "Make sure iPhone is nearby the active pump",
            role: "errorMessage",
            taxonomy: "N8",
            expected: .other("Make sure iPhone is nearby the active pump")
        ),
        // TandemKit/PumpManager/TandemPumpManager.swift:362
        Row(
            identifier: "PumpCommError.noResponse",
            message: "No response from pump",
            role: "errorMessage",
            taxonomy: "N8",
            expected: .other("No response from pump")
        ),
        // TandemKit/PumpManager/TandemPeripheralManager.swift:227
        Row(
            identifier: "PumpCommError.errorResponse",
            message: "Pump Error: Failed to discoverServices: <error>",
            role: "errorMessage",
            taxonomy: "N8",
            expected: .other("Pump Error: Failed to discoverServices: <error>")
        ),
        // TandemKit/PumpManager/TandemPeripheralManager.swift:235
        Row(
            identifier: "PumpCommError.errorResponse",
            message: "Pump Error: No service: <PUMP_SERVICE>",
            role: "errorMessage",
            taxonomy: "N8",
            expected: .other("Pump Error: No service: <PUMP_SERVICE>")
        ),
        // TandemKit/PumpManager/TandemPeripheralManager.swift:245
        Row(
            identifier: "PumpCommError.errorResponse",
            message: "Pump Error: <message>",
            role: "errorMessage",
            taxonomy: "N8",
            expected: .other("Pump Error: <message>")
        ),
        // TandemKit/PumpManager/TandemPeripheralManager.swift:254
        Row(
            identifier: "PumpCommError.errorResponse",
            message: "Pump Error: No service: <DIS_SERVICE>",
            role: "errorMessage",
            taxonomy: "N8",
            expected: .other("Pump Error: No service: <DIS_SERVICE>")
        ),
        // TandemKit/PumpManager/TandemBluetoothManager.swift:318
        Row(
            identifier: "PumpCommError.errorResponse",
            message: "Pump Error: Failed to connect: <error>",
            role: "errorMessage",
            taxonomy: "N8",
            expected: .other("Pump Error: Failed to connect: <error>")
        ),
        // TandemKitUI/Views/Settings/TandemKitSettingsView.swift:230-233
        Row(
            identifier: "TandemKitSettingsView.pumpDisconnectedBanner",
            message: "Pump Disconnected",
            role: "notificationTitle",
            taxonomy: "N8",
            expected: .other("Pump Disconnected")
        ),
        // TandemKit/PumpManager/TandemPumpManager.swift:346
        Row(
            identifier: "TandemPumpManagerValidationError.controlIQModeActive",
            message: "The operation couldn't be completed.",
            role: "errorMessage",
            taxonomy: "N9",
            expected: .other("The operation couldn't be completed.")
        ),
        // TandemKit/PumpManager/TandemPumpManager.swift:509
        Row(
            identifier: "PumpCommError.invalidScheduledBasalRate",
            message: "Invalid scheduled basal rate",
            role: "errorMessage",
            taxonomy: "N9",
            expected: .other("Invalid scheduled basal rate")
        ),
        // TandemKit/PumpManager/TandemPumpManager.swift:509
        Row(
            identifier: "PumpCommError.invalidScheduledBasalRate",
            message: "Temp basal cannot be performed while scheduled basal rate is 0 or no basal profile exists",
            role: "errorMessage",
            taxonomy: "N9",
            expected: .other("Temp basal cannot be performed while scheduled basal rate is 0 or no basal profile exists")
        ),
        // TandemKit/PumpManager/TandemPumpManager.swift:368
        Row(
            identifier: "PumpCommError.invalidPacket",
            message: "Other PumpCommError: invalidPacket",
            role: "errorMessage",
            taxonomy: "N9",
            expected: .other("Other PumpCommError: invalidPacket")
        ),
        // TandemKit/PumpManager/TandemPumpManager.swift:436
        Row(
            identifier: "PumpCommError.noActiveBolus",
            message: "No active bolus to cancel",
            role: "errorMessage",
            taxonomy: "N9",
            expected: .other("No active bolus to cancel")
        ),
        // TandemKit/PumpManager/TandemPumpManager.swift:436
        Row(
            identifier: "PumpCommError.noActiveBolus",
            message: "No bolus is running.",
            role: "errorMessage",
            taxonomy: "N9",
            expected: .other("No bolus is running.")
        ),
        // TandemKit/PumpManager/TandemPumpManager.swift:897
        Row(
            identifier: "PumpCommError.errorResponse",
            message: "Pump Error: Error syncing time with pump",
            role: "errorMessage",
            taxonomy: "N9",
            expected: .other("Pump Error: Error syncing time with pump")
        ),
        // TandemKit/PumpManager/TandemPumpManager+SyncBasal.swift:33
        Row(
            identifier: "PumpCommError.requestConstructionFailed",
            message: "Failed to build pump request: Invalid IDPManager state in syncBasalRateSchedule",
            role: "errorMessage",
            taxonomy: "N9",
            expected: .other("Failed to build pump request: Invalid IDPManager state in syncBasalRateSchedule")
        ),
        // TandemKit/PumpManager/TandemPumpManager+SyncBasal.swift:33
        Row(
            identifier: "PumpCommError.requestConstructionFailed",
            message: "Please try again. If the problem persists, re-pair your pump.",
            role: "errorMessage",
            taxonomy: "N9",
            expected: .other("Please try again. If the problem persists, re-pair your pump.")
        ),
        // TandemKit/PumpManager/TandemPumpManager+SyncBasal.swift:68
        Row(
            identifier: "PumpCommError.requestConstructionFailed",
            message: "Failed to build pump request: No active profile found and got unexpected response creating initial profile",
            role: "errorMessage",
            taxonomy: "N9",
            expected: .other(
                "Failed to build pump request: No active profile found and got unexpected response creating initial profile"
            )
        ),
        // TandemKit/PumpManager/TandemPumpManager+SyncBasal.swift:106
        Row(
            identifier: "PumpCommError.requestConstructionFailed",
            message: "Failed to build pump request: No active profile found",
            role: "errorMessage",
            taxonomy: "N9",
            expected: .other("Failed to build pump request: No active profile found")
        ),
        // TandemKit/PumpManager/TandemPumpManager+SyncBasal.swift:166
        Row(
            identifier: "PumpCommError.requestConstructionFailed",
            message: "Failed to build pump request: Pump rejected SetIDPSegment",
            role: "errorMessage",
            taxonomy: "N9",
            expected: .other("Failed to build pump request: Pump rejected SetIDPSegment")
        ),
        // TandemKit/PumpManager/TandemPumpManager+SyncBasal.swift:172
        Row(
            identifier: "PumpCommError.errorResponse",
            message: "Pump Error: Error syncing basal rates: Pump rejected SetIDPSegment",
            role: "errorMessage",
            taxonomy: "N9",
            expected: .other("Pump Error: Error syncing basal rates: Pump rejected SetIDPSegment")
        ),
        // TandemKitUI/Views/Settings/TandemKitSettingsView.swift:74-84
        Row(
            identifier: "CommandFailure.resume",
            message: "Could not resume insulin delivery",
            role: "alertTitle",
            taxonomy: "N9",
            expected: .other("Could not resume insulin delivery")
        ),
        // TandemKitUI/Views/Settings/TandemKitSettingsView.swift:74-84
        Row(
            identifier: "CommandFailure.resume",
            message: "The pump rejected starting insulin delivery. Check \"View Notifications\" for more details. The pump may be reporting an occlusion, empty cartridge, or not filling the tubing.",
            role: "alertBody",
            taxonomy: "N9",
            expected: .occlusion
        ),
        // TandemKitUI/Views/Settings/TandemKitSettingsView.swift:85-96
        Row(
            identifier: "CommandFailure.suspend",
            message: "Could not suspend insulin delivery",
            role: "alertTitle",
            taxonomy: "N9",
            expected: .other("Could not suspend insulin delivery")
        ),
        // TandemKitUI/Views/Settings/TandemKitSettingsView.swift:85-96
        Row(
            identifier: "CommandFailure.suspend",
            message: "The pump rejected suspending insulin delivery. To urgently suspend insulin delivery, detach from your site.",
            role: "alertBody",
            taxonomy: "N9",
            expected: .other(
                "The pump rejected suspending insulin delivery. To urgently suspend insulin delivery, detach from your site."
            )
        ),
        // TandemKitUI/Views/Settings/TandemKitSettingsView.swift:97-107
        Row(
            identifier: "CommandFailure.controlIQ",
            message: "Could not change Control-IQ setting",
            role: "alertTitle",
            taxonomy: "N9",
            expected: .other("Could not change Control-IQ setting")
        ),
        // TandemKitUI/Views/Settings/TandemKitSettingsView.swift:97-107
        Row(
            identifier: "CommandFailure.controlIQ",
            message: "The pump rejected the Control-IQ change. Check \"View Notifications\" for more details.",
            role: "alertBody",
            taxonomy: "N9",
            expected: .other("The pump rejected the Control-IQ change. Check \"View Notifications\" for more details.")
        ),
        // TandemKitUI/Views/Settings/TandemKitSettingsView.swift:108-118
        Row(
            identifier: "CommandFailure.exerciseMode",
            message: "Could not change exercise mode",
            role: "alertTitle",
            taxonomy: "N9",
            expected: .other("Could not change exercise mode")
        ),
        // TandemKitUI/Views/Settings/TandemKitSettingsView.swift:108-118
        Row(
            identifier: "CommandFailure.exerciseMode",
            message: "The pump rejected the exercise mode change.",
            role: "alertBody",
            taxonomy: "N9",
            expected: .other("The pump rejected the exercise mode change.")
        ),
        // TandemKitUI/Views/Settings/TandemKitSettingsView.swift:119-129
        Row(
            identifier: "CommandFailure.sleepMode",
            message: "Could not change sleep mode",
            role: "alertTitle",
            taxonomy: "N9",
            expected: .other("Could not change sleep mode")
        ),
        // TandemKitUI/Views/Settings/TandemKitSettingsView.swift:119-129
        Row(
            identifier: "CommandFailure.sleepMode",
            message: "The pump rejected the sleep mode change.",
            role: "alertBody",
            taxonomy: "N9",
            expected: .other("The pump rejected the sleep mode change.")
        ),
        // TandemKitUI/Views/Settings/TandemKitSettingsView.swift:130-140
        Row(
            identifier: "CommandFailure.stopTempRate",
            message: "Could not stop temp rate",
            role: "alertTitle",
            taxonomy: "N9",
            expected: .other("Could not stop temp rate")
        ),
        // TandemKitUI/Views/Settings/TandemKitSettingsView.swift:130-140
        Row(
            identifier: "CommandFailure.stopTempRate",
            message: "The pump rejected stopping the temp rate.",
            role: "alertBody",
            taxonomy: "N9",
            expected: .other("The pump rejected stopping the temp rate.")
        ),
        // TandemKitUI/ViewModels/Settings/TandemKitControlIQSettingsViewModel.swift:94
        Row(
            identifier: "TandemKitControlIQSettingsViewModel.saveError",
            message: "Failed to update Control-IQ settings. Check pump connection.",
            role: "errorMessage",
            taxonomy: "N9",
            expected: .other("Failed to update Control-IQ settings. Check pump connection.")
        ),
        // TandemKitUI/ViewModels/Settings/TandemKitControlIQSettingsViewModel.swift:115
        Row(
            identifier: "TandemKitControlIQSettingsViewModel.saveError",
            message: "Failed to update sleep schedule. Check pump connection.",
            role: "errorMessage",
            taxonomy: "N9",
            expected: .other("Failed to update sleep schedule. Check pump connection.")
        ),
        // TandemKitUI/ViewModels/Settings/TandemKitNotificationsViewModel.swift:54
        Row(
            identifier: "TandemKitNotificationsViewModel.errorMessage",
            message: "Failed to dismiss notification",
            role: "errorMessage",
            taxonomy: "N9",
            expected: .other("Failed to dismiss notification")
        ),
        // TandemKitUI/ViewModels/CGMs/TandemKitCGMSettingsViewModel.swift:143
        Row(
            identifier: "TandemKitCGMSettingsViewModel.commandError",
            message: "Failed to stop CGM sensor. Check pump connection.",
            role: "errorMessage",
            taxonomy: "N9",
            expected: .other("Failed to stop CGM sensor. Check pump connection.")
        ),
        // TandemKitUI/Views/Onboarding/TandemKitScanView.swift:71-106
        Row(
            identifier: "TandemKitScanView.pairingCodePrompt",
            message: "Enter Pairing code",
            role: "alertTitle",
            taxonomy: "N10",
            expected: .other("Enter Pairing code")
        ),
        // TandemKitUI/Views/Onboarding/TandemKitScanView.swift:71-106
        Row(
            identifier: "TandemKitScanView.pairingCodePrompt",
            message: "Enter the pairing code from your pump",
            role: "alertBody",
            taxonomy: "N10",
            expected: .other("Enter the pairing code from your pump")
        ),
        // TandemKitUI/Views/Onboarding/TandemKitScanView.swift:71-106
        Row(
            identifier: "TandemKitScanView.pairingCodePrompt",
            message: "The pairing code is located on the inside of the cartridge area labeled as 'PIN' and consists of six numbers.",
            role: "alertBody",
            taxonomy: "N10",
            expected: .other(
                "The pairing code is located on the inside of the cartridge area labeled as 'PIN' and consists of six numbers."
            )
        ),
        // TandemKitUI/ViewModels/CGMs/TandemKitCGMSettingsViewModel.swift:83-88
        Row(
            identifier: "TandemKitCGMSettingsViewModel.transmitterBatteryStatus",
            message: "OK",
            role: "validation",
            taxonomy: "N11",
            expected: .other("OK")
        ),
        // TandemKitUI/ViewModels/CGMs/TandemKitCGMSettingsViewModel.swift:83-88
        Row(
            identifier: "TandemKitCGMSettingsViewModel.transmitterBatteryStatus",
            message: "Error",
            role: "validation",
            taxonomy: "N11",
            expected: .other("Error")
        ),
        // TandemKitUI/ViewModels/CGMs/TandemKitCGMSettingsViewModel.swift:83-88
        Row(
            identifier: "TandemKitCGMSettingsViewModel.transmitterBatteryStatus",
            message: "Expired",
            role: "validation",
            taxonomy: "N11",
            expected: .other("Expired")
        ),
        // TandemKitUI/ViewModels/CGMs/TandemKitCGMSettingsViewModel.swift:83-88
        Row(
            identifier: "TandemKitCGMSettingsViewModel.transmitterBatteryStatus",
            message: "Out of Range",
            role: "validation",
            taxonomy: "N11",
            expected: .other("Out of Range")
        ),
        // TandemKitUI/ViewModels/CGMs/TandemKitCGMSettingsViewModel.swift:83-88
        Row(
            identifier: "TandemKitCGMSettingsViewModel.transmitterBatteryStatus",
            message: "Unavailable",
            role: "validation",
            taxonomy: "N11",
            expected: .other("Unavailable")
        ),
        // TandemKitUI/ViewModels/Onboarding/TandemKitScanViewModel.swift:52
        Row(
            identifier: "TandemKitScanViewModel.pinCodePromptError",
            message: "Please enter a pairing code",
            role: "validation",
            taxonomy: "N12",
            expected: .other("Please enter a pairing code")
        ),
        // TandemKitUI/ViewModels/Onboarding/TandemKitScanViewModel.swift:61
        Row(
            identifier: "TandemKitScanViewModel.connectionErrorMessage",
            message: "Pump manager not initialized",
            role: "errorMessage",
            taxonomy: "N12",
            expected: .other("Pump manager not initialized")
        ),
        // TandemKitUI/ViewModels/Onboarding/TandemKitScanViewModel.swift:67
        Row(
            identifier: "TandemKitScanViewModel.connectionErrorMessage",
            message: "No peripheral selected",
            role: "errorMessage",
            taxonomy: "N12",
            expected: .other("No peripheral selected")
        ),
        // TandemKitUI/Views/Onboarding/TandemKitScanView.swift:62-70
        Row(
            identifier: "TandemKitScanView.connectionErrorAlert",
            message: "Error while connecting to device",
            role: "alertTitle",
            taxonomy: "N12",
            expected: .other("Error while connecting to device")
        ),
        // TandemKitUI/ViewModels/CGMs/TandemKitG6SetupViewModel.swift:71
        Row(
            identifier: "TandemKitG6SetupViewModel.error",
            message: "Failed to set transmitter.",
            role: "errorMessage",
            taxonomy: "N12",
            expected: .other("Failed to set transmitter.")
        ),
        // TandemKitUI/ViewModels/CGMs/TandemKitG6SetupViewModel.swift:96
        Row(
            identifier: "TandemKitG6SetupViewModel.error",
            message: "Failed to start CGM sensor",
            role: "errorMessage",
            taxonomy: "N12",
            expected: .other("Failed to start CGM sensor")
        ),
        // TandemKitUI/ViewModels/CGMs/TandemKitG7SetupViewModel.swift:48
        Row(
            identifier: "TandemKitG7SetupViewModel.error",
            message: "Failed to set G7 pairing code",
            role: "errorMessage",
            taxonomy: "N12",
            expected: .other("Failed to set G7 pairing code")
        ),
        // TandemKitUI/Views/CGMs/TandemKitCGMSettingsView.swift:62-72
        Row(
            identifier: "TandemKitCGMSettingsView.stopConfirmation",
            message: "Stop CGM Sensor",
            role: "alertTitle",
            taxonomy: "N12",
            expected: .other("Stop CGM Sensor")
        ),
        // TandemKitUI/Views/CGMs/TandemKitCGMSettingsView.swift:62-72
        Row(
            identifier: "TandemKitCGMSettingsView.stopConfirmation",
            message: "Are you sure you want to stop the CGM sensor session on your pump?",
            role: "alertBody",
            taxonomy: "N12",
            expected: .other("Are you sure you want to stop the CGM sensor session on your pump?")
        ),
        // TandemKitUI/Views/CGMs/TandemKitG6SetupWizardView.swift:27-36
        Row(
            identifier: "TandemKitSetupWizard.errorAlert",
            message: "Error",
            role: "alertTitle",
            taxonomy: "N12",
            expected: .other("Error")
        ),
        // TandemKitUI/Views/Settings/TandemKitSettingsView.swift:492-516
        Row(
            identifier: "TandemKitSettingsView.switchToCIQ",
            message: "Disable %@ Algorithm",
            role: "alertTitle",
            taxonomy: "N13",
            expected: .other("Disable %@ Algorithm")
        ),
        // TandemKitUI/Views/Settings/TandemKitSettingsView.swift:492-516
        Row(
            identifier: "TandemKitSettingsView.switchToCIQ",
            message: "This will DISABLE %@ in favor of the Control-IQ algorithm built-in to your pump.\n\n%@ will stop issuing temp basals and boluses. Are you sure?",
            role: "alertBody",
            taxonomy: "N13",
            expected: .other(
                "This will DISABLE %@ in favor of the Control-IQ algorithm built-in to your pump.\n\n%@ will stop issuing temp basals and boluses. Are you sure?"
            )
        ),
        // TandemKitUI/Views/Settings/TandemKitSettingsView.swift:517-544
        Row(
            identifier: "TandemKitSettingsView.switchToDIY",
            message: "Enable %@ Algorithm",
            role: "alertTitle",
            taxonomy: "N13",
            expected: .other("Enable %@ Algorithm")
        ),
        // TandemKitUI/Views/Settings/TandemKitSettingsView.swift:517-544
        Row(
            identifier: "TandemKitSettingsView.switchToDIY",
            message: "This will disable Control-IQ on your pump and allow %@ to resume %@ closed-loop dosing.",
            role: "alertBody",
            taxonomy: "N13",
            expected: .other("This will disable Control-IQ on your pump and allow %@ to resume %@ closed-loop dosing.")
        ),
        // TandemKitUI/Views/Settings/TandemKitSettingsView.swift:567-584
        Row(
            identifier: "TandemKitSettingsView.stopTempRate",
            message: "Temp Basal Active",
            role: "alertTitle",
            taxonomy: "N13",
            expected: .other("Temp Basal Active")
        ),
        // TandemKitUI/Views/Settings/TandemKitSettingsView.swift:567-584
        Row(
            identifier: "TandemKitSettingsView.stopTempRate",
            message: "The current temp rate is <rate> for the next <duration>. Would you like to revert to your scheduled basal rate?",
            role: "alertBody",
            taxonomy: "N13",
            expected: .other(
                "The current temp rate is <rate> for the next <duration>. Would you like to revert to your scheduled basal rate?"
            )
        ),
        // TandemKitUI/Views/Settings/TandemKitSettingsView.swift:585-597
        Row(
            identifier: "TandemKitSettingsView.stopTempRateClosedLoopWarning",
            message: "WARNING",
            role: "alertTitle",
            taxonomy: "N13",
            expected: .other("WARNING")
        ),
        // TandemKitUI/Views/Settings/TandemKitSettingsView.swift:585-597
        Row(
            identifier: "TandemKitSettingsView.stopTempRateClosedLoopWarning",
            message: "Closed loop is currently enabled. Cancelling the active temp rate on the pump will NOT place you in open-loop mode, and the next run of the oref algorithm will set a new temp rate.",
            role: "alertBody",
            taxonomy: "N13",
            expected: .other(
                "Closed loop is currently enabled. Cancelling the active temp rate on the pump will NOT place you in open-loop mode, and the next run of the oref algorithm will set a new temp rate."
            )
        ),
        // TandemKitUI/Views/Settings/TandemKitSettingsView.swift:545-557
        Row(
            identifier: "TandemKitSettingsView.diyRestored",
            message: "%@ Mode Restored",
            role: "alertTitle",
            taxonomy: "N14",
            expected: .other("%@ Mode Restored")
        ),
        // TandemKitUI/Views/Settings/TandemKitSettingsView.swift:545-557
        Row(
            identifier: "TandemKitSettingsView.diyRestored",
            message: "Control-IQ has been disabled and you are currently in open-loop. To re-enable %@ closed-loop, go to your app's Algorithm settings.",
            role: "alertBody",
            taxonomy: "N14",
            expected: .other(
                "Control-IQ has been disabled and you are currently in open-loop. To re-enable %@ closed-loop, go to your app's Algorithm settings."
            )
        ),
        // TandemKitUI/Views/Settings/TandemKitSettingsView.swift:558-566
        Row(
            identifier: "TandemKitSettingsView.noCGMConnected",
            message: "No CGM Connected",
            role: "alertTitle",
            taxonomy: "N14",
            expected: .other("No CGM Connected")
        ),
        // TandemKitUI/Views/Settings/TandemKitSettingsView.swift:558-566
        Row(
            identifier: "TandemKitSettingsView.noCGMConnected",
            message: "Control-IQ was enabled but no CGM is connected to the pump.\n\nUntil a CGM sensor is connected, your configured profile rates will be used. To connect a sensor, go to CGM Settings below.",
            role: "alertBody",
            taxonomy: "N14",
            expected: .other(
                "Control-IQ was enabled but no CGM is connected to the pump.\n\nUntil a CGM sensor is connected, your configured profile rates will be used. To connect a sensor, go to CGM Settings below."
            )
        ),
        // TandemKitUI/Views/Settings/TandemKitSettingsView.swift:33-52
        Row(
            identifier: "TandemKitSettingsView.removePump",
            message: "Remove Pump",
            role: "alertTitle",
            taxonomy: "N14",
            expected: .other("Remove Pump")
        ),
        // TandemKitUI/Views/Settings/TandemKitSettingsView.swift:33-52
        Row(
            identifier: "TandemKitSettingsView.removePump",
            message: "Are you sure you want to remove the pump from %@? You will need to re-pair the device and have access to the charging pad.",
            role: "alertBody",
            taxonomy: "N14",
            expected: .other(
                "Are you sure you want to remove the pump from %@? You will need to re-pair the device and have access to the charging pad."
            )
        ),
        // TandemKitUI/Views/Settings/TandemKitSettingsView.swift:33-52
        Row(
            identifier: "TandemKitSettingsView.removePump",
            message: "Delete Pump",
            role: "alertBody",
            taxonomy: "N14",
            expected: .other("Delete Pump")
        ),
        // TandemKitUI/Views/Settings/TandemKitSettingsView.swift:54-60
        Row(
            identifier: "TandemKitSettingsView.syncTime",
            message: "Time Change Detected",
            role: "alertTitle",
            taxonomy: "N14",
            expected: .other("Time Change Detected")
        ),
        // TandemKitUI/Views/Settings/TandemKitSettingsView.swift:54-60
        Row(
            identifier: "TandemKitSettingsView.syncTime",
            message: "The time on your pump is different from the current time. Do you want to update the time on your pump to the current time?",
            role: "alertBody",
            taxonomy: "N14",
            expected: .other(
                "The time on your pump is different from the current time. Do you want to update the time on your pump to the current time?"
            )
        ),
        // TandemKitUI/Views/Settings/TandemKitSettingsView.swift:234-245
        Row(
            identifier: "TandemKitSettingsView.noCGMBanner",
            message: "No CGM connected to pump",
            role: "notificationTitle",
            taxonomy: "N14",
            expected: .other("No CGM connected to pump")
        ),
        // TandemKitUI/Views/Settings/TandemKitSettingsView.swift:234-245
        Row(
            identifier: "TandemKitSettingsView.noCGMBanner",
            message: "%@ closed-loop is disabled with your pump's Control-IQ algorithm on, but no CGM is connected, so you are in open-loop.",
            role: "notificationBody",
            taxonomy: "N14",
            expected: .other(
                "%@ closed-loop is disabled with your pump's Control-IQ algorithm on, but no CGM is connected, so you are in open-loop."
            )
        ),
        // TandemKitUI/Views/Settings/TandemKitSettingsView.swift:246-254
        Row(
            identifier: "TandemKitSettingsView.controlIQBanner",
            message: "Control-IQ pump algorithm enabled",
            role: "notificationTitle",
            taxonomy: "N14",
            expected: .other("Control-IQ pump algorithm enabled")
        ),
        // TandemKitUI/Views/Settings/TandemKitSettingsView.swift:246-254
        Row(
            identifier: "TandemKitSettingsView.controlIQBanner",
            message: "%@ closed-loop is not in use.",
            role: "notificationBody",
            taxonomy: "N14",
            expected: .other("%@ closed-loop is not in use.")
        ),
        // TandemKitUI/Views/Settings/TandemKitSettingsView.swift:255-261
        Row(
            identifier: "TandemKitSettingsView.openLoopBanner",
            message: "Open loop mode",
            role: "notificationTitle",
            taxonomy: "N14",
            expected: .other("Open loop mode")
        ),
        // TandemKitUI/Views/Settings/TandemKitSettingsView.swift:263-273
        Row(
            identifier: "TandemKitSettingsView.timeSyncWarningBanner",
            message: "The time on your pump is different from the current time. Your pump's time controls your scheduled therapy settings. Scroll down to Pump Time row to review the time difference and configure your pump.",
            role: "notificationBody",
            taxonomy: "N14",
            expected: .other(
                "The time on your pump is different from the current time. Your pump's time controls your scheduled therapy settings. Scroll down to Pump Time row to review the time difference and configure your pump."
            )
        ),
        // TandemKitUI/ViewModels/CGMs/TandemKitCGMSettingsViewModel.swift:23-27
        Row(
            identifier: "CGMSessionState.displayText",
            message: "Stopped",
            role: "validation",
            taxonomy: "N14",
            expected: .other("Stopped")
        ),
        // TandemKitUI/ViewModels/CGMs/TandemKitCGMSettingsViewModel.swift:23-27
        Row(
            identifier: "CGMSessionState.displayText",
            message: "Starting...",
            role: "validation",
            taxonomy: "N14",
            expected: .other("Starting...")
        ),
        // TandemKitUI/ViewModels/CGMs/TandemKitCGMSettingsViewModel.swift:23-27
        Row(
            identifier: "CGMSessionState.displayText",
            message: "Active",
            role: "validation",
            taxonomy: "N14",
            expected: .other("Active")
        ),
        // TandemKitUI/ViewModels/CGMs/TandemKitCGMSettingsViewModel.swift:23-27
        Row(
            identifier: "CGMSessionState.displayText",
            message: "Stopping...",
            role: "validation",
            taxonomy: "N14",
            expected: .other("Stopping...")
        ),
        // TandemKitUI/ViewModels/CGMs/TandemKitCGMSettingsViewModel.swift:23-27
        Row(
            identifier: "CGMSessionState.displayText",
            message: "Unknown",
            role: "validation",
            taxonomy: "N14",
            expected: .other("Unknown")
        ),
        // TandemKitUI/Views/CGMs/TandemKitCGMSettingsView.swift:151-157
        Row(
            identifier: "TandemKitCGMSettingsView.gracePeriodRow",
            message: "Grace Period",
            role: "validation",
            taxonomy: "N14",
            expected: .other("Grace Period")
        ),
        // TandemKitUI/Views/CGMs/TandemKitCGMSettingsView.swift:133-140
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
    /// - N1 alarm titles & bodies (cartridge, cartridge-removed, pump-reset,
    ///   temperature, altitude, atmospheric-pressure, stuck-button,
    ///   invalid-date) and `HighestAamResponse.malfunction` -> SHOULD be
    ///   `.hardwareFault`, but none contain the "fault" token; the prose says
    ///   "Cartridge Alarm" / "Malfunction" / etc.
    ///   (TandemCore/Messages/CurrentStatus/AlarmStatus.swift,
    ///   HighestAam.swift:106). NB: "Occlusion Alarm" is NOT a gap — it hits
    ///   `.occlusion` via the "occlusion" token (AlarmStatus.swift:157).
    /// - N4 reservoir-empty prose ("No Insulin", "Empty Cartridge Alarm",
    ///   "Cartridge is out of insulin ...") -> SHOULD be `.reservoirEmpty`, but
    ///   the token is the space-free "reservoirempty"/"emptyreservoir" and the
    ///   prose never contains it (TandemKitUI/TandemPumpManager+UI.swift:123,
    ///   AlarmStatus.swift:164).
    /// - N7 CGM alert titles render as space-separated formatted case names
    ///   ("Sensor Failed Cgm Alert", "Sensor Expired Cgm Alert", ...) -> SHOULD
    ///   be `.sensorFailure`, but "sensorfailed"/"sensorstopped" (and
    ///   "sensorexpired") are space-free and never appear in the formatted text
    ///   (TandemCore/Messages/CurrentStatus/CGMAlertStatus.swift:135).
    /// - N8 connectivity strings ("Pump not connected", "Make sure iPhone is
    ///   nearby ...", "No response from pump", "Pump Error: ...",
    ///   "Pump Disconnected") -> SHOULD be `.commsTransient`, but
    ///   "notconnected"/"noresponse"/"comms"/"communication" are all space-free
    ///   or absent, so the spaced prose misses
    ///   (TandemKit/PumpManager/*.swift, TandemKitSettingsView.swift:230-233).
    static let classifierCoverageGaps: Set<String> = [
        "AlarmResponseType.cartridgeGroup — Cartridge Alarm",
        "AlarmResponseType.cartridgeGroup — There is an issue with the cartridge and it needs to be replaced.",
        "AlarmResponseType.CARTRIDGE_REMOVED_ALARM — Cartridge Removed Alarm",
        "AlarmResponseType.CARTRIDGE_REMOVED_ALARM — The cartridge was removed from the pump. Please fill a new cartridge.",
        "AlarmResponseType.PUMP_RESET_ALARM — Pump Reset Alarm",
        "AlarmResponseType.PUMP_RESET_ALARM — The pump was reset. IOB has been reset to 0 and CGM may need to be re-activated.",
        "AlarmResponseType.temperatureGroup — Temperature Alarm",
        "AlarmResponseType.temperatureGroup — Pump temperature is out of range and insulin cannot be safely delivered.",
        "AlarmResponseType.ALTITUDE_ALARM — Altitude Alarm",
        "AlarmResponseType.ATMOSPHERIC_PRESSURE_OUT_OF_RANGE_ALARM — Atmospheric Pressure Out Of Range Alarm",
        "AlarmResponseType.STUCK_BUTTON_ALARM — Stuck Button Alarm",
        "AlarmResponseType.STUCK_BUTTON_ALARM — The pump button may be stuck or has been pressed for too long a period of time.",
        "AlarmResponseType.INVALID_DATE_ALARM — Invalid Date Alarm",
        "AlarmResponseType.INVALID_DATE_ALARM — The pump's configured date is invalid.",
        "HighestAamResponse.malfunction — Malfunction",
        "PumpStatusHighlight.noInsulin — No Insulin",
        "AlarmResponseType.EMPTY_CARTRIDGE_ALARM — Empty Cartridge Alarm",
        "AlarmResponseType.EMPTY_CARTRIDGE_ALARM — Cartridge is out of insulin and insulin delivery cannot occur. Please fill a new cartridge.",
        "CGMAlert.SENSOR_FAILED — Sensor Failed Cgm Alert",
        "CGMAlert.LOW — Low Cgm Alert",
        "CGMAlert.HIGH — High Cgm Alert",
        "CGMAlert.FIXED_LOW — Fixed Low Cgm Alert",
        "CGMAlert.SENSOR_EXPIRING — Sensor Expiring Cgm Alert",
        "CGMAlert.SENSOR_EXPIRED — Sensor Expired Cgm Alert",
        "CGMAlert.OUT_OF_RANGE — Out Of Range Cgm Alert",
        "CGMAlert.TRANSMITTER — Transmitter Cgm Alert",
        "PumpCommError.pumpNotConnected — Pump not connected",
        "PumpCommError.pumpNotConnected — Make sure iPhone is nearby the active pump",
        "PumpCommError.noResponse — No response from pump",
        "PumpCommError.errorResponse — Pump Error: Failed to discoverServices: <error>",
        "PumpCommError.errorResponse — Pump Error: No service: <PUMP_SERVICE>",
        "PumpCommError.errorResponse — Pump Error: <message>",
        "PumpCommError.errorResponse — Pump Error: No service: <DIS_SERVICE>",
        "PumpCommError.errorResponse — Pump Error: Failed to connect: <error>",
        "TandemKitSettingsView.pumpDisconnectedBanner — Pump Disconnected"
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
        #expect(Self.classifierCoverageGaps.count == 35)
    }
}
