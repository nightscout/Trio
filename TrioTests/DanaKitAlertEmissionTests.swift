import DanaKit
import Foundation
import LoopKit
import Testing

@testable import Trio

/// Pins the levels DanaKit issues its LoopKit Alerts with
/// (`DanaKit/PumpManager/PumpManagerAlert.swift`,
/// `Common/DanaKitNotification.swift`,
/// `DanaKit/PumpManager/DanaKitPumpManager.swift`).
///
/// What this suite pins:
///  - The level DanaKit declares in `DanaKitPumpManager.issuableAlerts` for
///    every alert it issues (the pump alarms plus the two disconnect
///    reminders), and that Trio applies the Device Alarms tiers to each under
///    the issued managerIdentifier "Dana".
///  - The documented escalation gaps, as a ratchet that fails when a gap is
///    fixed (forcing this file to be updated).
///
/// No classifier rows: every `DanaKitPumpManagerError` reaching
/// `APSManager.processError` is wrapped in LoopKit's `PumpManagerError` before
/// leaving the completion handler, so the exact `String(describing:)` input is
/// the wrapping, not the Dana case name. That input cannot be stated from the
/// synthesis audit alone, so classifier rows are omitted rather than guessed.
///
/// One-line gap summary: three taxonomy-Critical emissions are issued below
/// critical — `basalMax` and `dailyMax` (N2 Delivery Suspended/Stopped) at
/// `.active`, and `unknown` (N1 Hardware Fault catch-all) at `.timeSensitive`
/// — so a daily/basal hard stop or an unrecognized pump alarm reaches the user
/// below critical.
@Suite("Trio Alert Emission: DanaKit") struct DanaKitAlertEmissionTests {
    private func id(_ manager: String, _ alertID: String) -> Alert.Identifier {
        Alert.Identifier(managerIdentifier: manager, alertIdentifier: alertID)
    }

    /// The managerIdentifier DanaKit issues with.
    private static let emittedManagerIdentifier = "Dana"

    /// Emitted alerts. `level` is the level DanaKit issues and declares;
    /// `taxonomyLevel` is what the row should be per taxonomy.
    struct Row {
        let alertIdentifier: String
        let level: Alert.InterruptionLevel
        let taxonomyLevel: Alert.InterruptionLevel
    }

    private static let rows: [Row] = [
        // N5-pump -> .critical.
        Row(alertIdentifier: "batteryZeroPercent", level: .critical, taxonomyLevel: .critical),
        // N1 Hardware Fault -> .critical.
        Row(alertIdentifier: "pumpError", level: .critical, taxonomyLevel: .critical),
        // N1 -> .critical.
        Row(alertIdentifier: "occlusion", level: .critical, taxonomyLevel: .critical),
        // F2 Battery Low (High) -> .timeSensitive.
        Row(alertIdentifier: "lowBattery", level: .timeSensitive, taxonomyLevel: .timeSensitive),
        // N2 Delivery Suspended -> .critical.
        Row(alertIdentifier: "shutdown", level: .critical, taxonomyLevel: .critical),
        // N14 Informational/Status -> .active.
        Row(alertIdentifier: "basalCompare", level: .active, taxonomyLevel: .active),
        // N14 -> .active. Codes 0x07/0xFF both map here.
        Row(alertIdentifier: "bloodSugarMeasure", level: .active, taxonomyLevel: .active),
        // F1 Insulin Supply Low (High) -> .timeSensitive. Codes 0x08/0xFE both map here.
        Row(alertIdentifier: "remainingInsulinLevel", level: .timeSensitive, taxonomyLevel: .timeSensitive),
        // N4 Reservoir Empty -> .critical.
        Row(alertIdentifier: "emptyReservoir", level: .critical, taxonomyLevel: .critical),
        // N1 Hardware Fault -> .critical.
        Row(alertIdentifier: "checkShaft", level: .critical, taxonomyLevel: .critical),
        // N2 Delivery Suspended/Stopped -> .critical. GAP: issued .active.
        Row(alertIdentifier: "basalMax", level: .active, taxonomyLevel: .critical),
        // N2 -> .critical. GAP: issued .active.
        Row(alertIdentifier: "dailyMax", level: .active, taxonomyLevel: .critical),
        // N14 Informational/Status -> .active.
        Row(alertIdentifier: "bloodSugarCheckMiss", level: .active, taxonomyLevel: .active),
        // N1 Hardware Fault catch-all for unmapped alarm codes -> .critical.
        // GAP: issued .timeSensitive.
        Row(alertIdentifier: "unknown", level: .timeSensitive, taxonomyLevel: .critical),
        // N8 Connectivity (Medium) -> .timeSensitive. DanaKitNotification.
        Row(
            alertIdentifier: "com.bastiaanv.continuous-ble.disconnect-warning",
            level: .timeSensitive,
            taxonomyLevel: .timeSensitive
        ),
        // N8 -> .timeSensitive. DanaKitNotification, delayed by the user's reminder setting.
        Row(
            alertIdentifier: "com.bastiaanv.continuous-ble.disconnect-reminder",
            level: .timeSensitive,
            taxonomyLevel: .timeSensitive
        )
    ]

    private static func declaredLevel(_ alertID: String) -> Alert.InterruptionLevel? {
        DanaKitPumpManager.issuableAlerts.first { $0.identifier == alertID }?.interruptionLevel
    }

    /// Severity rank for comparing interruption levels (higher == more severe).
    private static func severity(_ level: Alert.InterruptionLevel) -> Int {
        switch level {
        case .active: return 0
        case .timeSensitive: return 1
        case .critical: return 2
        @unknown default: return -1
        }
    }

    // MARK: - Declared levels (CURRENT, must be green)

    @Test(
        "declared level is pinned and follows the Device Alarms tiers for every emitted alert",
        arguments: rows
    ) func declaredLevelPinned(_ row: Row) {
        #expect(Self.declaredLevel(row.alertIdentifier) == row.level)
        #expect(BaseTrioAlertManager.followsDeviceTiers(id(Self.emittedManagerIdentifier, row.alertIdentifier)))
    }

    /// `ble5InvalidKeys` is defined but never issued (the equivalent text is an
    /// ad hoc SwiftUI string in `DanaKitScanViewModel`), so it is not declared.
    @Test("declared alerts are exactly the pinned rows, each declared once") func declaredAlertsMatchRows() {
        let declared = DanaKitPumpManager.issuableAlerts.map(\.identifier)
        #expect(declared.count == Set(declared).count)
        #expect(Set(declared) == Set(Self.rows.map(\.alertIdentifier)))
        #expect(!declared.contains("ble5InvalidKeys"))
    }

    // MARK: - Known escalation gaps (ratchet)

    /// AlertIdentifiers whose declared level is LESS severe than their
    /// taxonomy level today. Documented expectation per identifier:
    ///
    ///  - "basalMax": SHOULD be `.critical` (taxonomy N2 Delivery
    ///    Suspended/Stopped); issued `.active`. A basal hard stop reaches the
    ///    user below critical.
    ///
    ///  - "dailyMax": SHOULD be `.critical` (taxonomy N2); issued `.active`. A
    ///    daily-insulin hard stop reaches the user below critical.
    ///
    ///  - "unknown": SHOULD be `.critical` (taxonomy N1 Hardware Fault). This
    ///    is the catch-all for unmapped pump alarm codes; issued
    ///    `.timeSensitive`, so an unrecognized pump alarm reaches the user
    ///    below critical.
    ///
    /// (basalMax/dailyMax carry warning-style copy — "contact your distributer
    /// to increase the limit" — so the N2 classification itself may warrant
    /// review; as mapped per classified.md they are gaps.)
    ///
    /// This stays green now and FAILS (prompting an update here) once a gap is
    /// closed in DanaKit.
    private static let knownEscalationGaps: Set<String> = [
        "basalMax",
        "dailyMax",
        "unknown"
    ]

    @Test("known escalation gaps are exactly as documented") func knownEscalationGapsExact() {
        let computed = Set(
            Self.rows
                .filter { Self.severity(Self.declaredLevel($0.alertIdentifier) ?? .active) < Self.severity($0.taxonomyLevel) }
                .map(\.alertIdentifier)
        )
        #expect(computed == Self.knownEscalationGaps)
    }
}

// MARK: - Message Classification

/// SPEC — How DanaKit's reportable user-facing messages are handled by
/// `TrioAlertClassifier.categorize(error:)`.
///
/// IMPORTANT — what production actually feeds the classifier vs. what this
/// suite feeds: in prod, `categorize(error:)` falls through to
/// `categorize(pumpError:)`, which keys off `String(describing: error)` — i.e.
/// the Swift *case name* of the error value (e.g. "noConnection",
/// "failedTempBasalAdjustment"), NOT the human-readable display copy. This
/// suite instead catalogs every reportable DanaKit *message* (alert titles /
/// bodies, error descriptions, notification copy, onboarding/validation
/// strings) with its emission identifier, and pins how the ordered substring
/// classifier would route that exact natural-language text.
///
/// Why almost everything lands in `.other`: `categorize(pumpError:)`
/// lowercases the string and runs ordered `contains` checks for concatenated
/// tokens ("uncertaindelivery", "occlusion", "reservoirempty", "fault",
/// "timeout", "communication", "bolusfailed", ...). Natural prose rarely
/// contains those exact (space-free) tokens, so it falls through to
/// `.other(originalString)`. The only natural matches here are:
///   - the occlusion alert TITLE ("Occlusion" contains "occlusion") ->
///     `.occlusion`; its BODY ("Check the reservoir and infus...") does NOT,
///     so the body is a gap.
///   - connectivity strings that literally contain the word "timeout"
///     ("Connection timeout is hit...", "Timeout has been hit...",
///     "A bolus timeout is active...") -> `.commsTransient`.
/// Notably the reservoir-empty copy ("Reservoir is empty. Replace it now!" /
/// "Empty reservoir") does NOT contain "reservoirempty"/"emptyreservoir" (the
/// space breaks the token), so it falls to `.other` despite an N4 taxonomy.
///
/// Each `Row` pairs an emission identifier with its exact display string and
/// pins the category `categorize(error:)` returns for that string TODAY. The
/// pinned `expected` reflects the classifier's ACTUAL output on the verbatim
/// message (green by construction); see the per-row sourceRef comments, which
/// cite the managers / pump / DanaKit sources
/// (`DanaKit/Packets/DanaNotifyAlarm.swift`,
/// `DanaKit/PumpManager/*.swift`, `DanaKit/Packets/DanaBolusStart.swift`,
/// `DanaKitUI/*`, `Common/NotificationHelper.swift`).
@Suite("Trio Alert Emission: DanaKit — Classification") struct DanaKitMessageClassificationTests {
    /// An error whose `String(describing:)` is exactly the catalogued display
    /// string, so the classifier matches over the real natural-language text.
    private struct StubError: Error, CustomStringConvertible { let description: String }

    /// One reportable DanaKit emission: its emission `identifier`, the exact
    /// `message` text, its `role` (alertTitle/alertBody/errorMessage/
    /// notificationTitle/notificationBody/validation), the `taxonomy` category,
    /// the `taxonomyBucket` it belongs to, and the `expected` category
    /// `categorize(error:)` returns for that message TODAY. `.other(message)`
    /// carries the EXACT original string.
    struct Row {
        let identifier: String
        let message: String
        let role: String
        let taxonomy: String
        let taxonomyBucket: String
        let expected: TrioAlertCategory
    }

    static let rows: [Row] = [
        // DanaKit/Packets/DanaNotifyAlarm.swift:11
        Row(
            identifier: "batteryZeroPercent",
            message: "Pump battery 0%",
            role: "alertTitle",
            taxonomy: "N5 Battery Dead / Power Lost",
            taxonomyBucket: "other",
            expected: .other("Pump battery 0%")
        ),
        // DanaKit/Packets/DanaNotifyAlarm.swift:11
        Row(
            identifier: "batteryZeroPercent",
            message: "Battery is empty. Replace it now!",
            role: "alertBody",
            taxonomy: "N5 Battery Dead / Power Lost",
            taxonomyBucket: "other",
            expected: .other("Battery is empty. Replace it now!")
        ),
        // DanaKit/Packets/DanaNotifyAlarm.swift:12
        Row(
            identifier: "pumpError",
            message: "Pump error",
            role: "alertTitle",
            taxonomy: "N1 Hardware Fault / Device Alarm",
            taxonomyBucket: "hardwareFault",
            expected: .other("Pump error")
        ),
        // DanaKit/Packets/DanaNotifyAlarm.swift:12
        Row(
            identifier: "pumpError",
            message: "Check the pump and try again",
            role: "alertBody",
            taxonomy: "N1 Hardware Fault / Device Alarm",
            taxonomyBucket: "hardwareFault",
            expected: .other("Check the pump and try again")
        ),
        // DanaKit/Packets/DanaNotifyAlarm.swift:13
        Row(
            identifier: "occlusion",
            message: "Occlusion",
            role: "alertTitle",
            taxonomy: "N1 Hardware Fault / Device Alarm",
            taxonomyBucket: "occlusion",
            expected: .occlusion
        ),
        // DanaKit/Packets/DanaNotifyAlarm.swift:13
        Row(
            identifier: "occlusion",
            message: "Check the reservoir and infus and try again",
            role: "alertBody",
            taxonomy: "N1 Hardware Fault / Device Alarm",
            taxonomyBucket: "occlusion",
            expected: .other("Check the reservoir and infus and try again")
        ),
        // DanaKit/Packets/DanaNotifyAlarm.swift:14
        Row(
            identifier: "lowBattery",
            message: "Low pump battery",
            role: "alertTitle",
            taxonomy: "F2 Battery Low (Warning)",
            taxonomyBucket: "other",
            expected: .other("Low pump battery")
        ),
        // DanaKit/Packets/DanaNotifyAlarm.swift:14
        Row(
            identifier: "lowBattery",
            message: "Pump battery needs to be replaced soon",
            role: "alertBody",
            taxonomy: "F2 Battery Low (Warning)",
            taxonomyBucket: "other",
            expected: .other("Pump battery needs to be replaced soon")
        ),
        // DanaKit/Packets/DanaNotifyAlarm.swift:15
        Row(
            identifier: "shutdown",
            message: "Pump shutdown",
            role: "alertTitle",
            taxonomy: "N2 Delivery Suspended / Stopped",
            taxonomyBucket: "other",
            expected: .other("Pump shutdown")
        ),
        // DanaKit/Packets/DanaNotifyAlarm.swift:15
        Row(
            identifier: "shutdown",
            message: "There has not been any interactions with the pump for too long. Either disable this function in the pump or interact with the pump",
            role: "alertBody",
            taxonomy: "N2 Delivery Suspended / Stopped",
            taxonomyBucket: "other",
            expected: .other(
                "There has not been any interactions with the pump for too long. Either disable this function in the pump or interact with the pump"
            )
        ),
        // DanaKit/Packets/DanaNotifyAlarm.swift:16
        Row(
            identifier: "basalCompare",
            message: "Basal Compare",
            role: "alertTitle",
            taxonomy: "N14 Informational / Status",
            taxonomyBucket: "other",
            expected: .other("Basal Compare")
        ),
        // DanaKit/Packets/DanaNotifyAlarm.swift:17 (alarm 0x07); :18 (alarm 0xFF)
        Row(
            identifier: "bloodSugarMeasure",
            message: "Blood glucose Measure",
            role: "alertTitle",
            taxonomy: "N14 Informational / Status",
            taxonomyBucket: "other",
            expected: .other("Blood glucose Measure")
        ),
        // DanaKit/Packets/DanaNotifyAlarm.swift:19 (alarm 0x08); :20 (alarm 0xFE)
        Row(
            identifier: "remainingInsulinLevel",
            message: "Remaining insulin level",
            role: "alertTitle",
            taxonomy: "F1 Insulin Supply Low (Warning)",
            taxonomyBucket: "reservoirLow",
            expected: .other("Remaining insulin level")
        ),
        // DanaKit/Packets/DanaNotifyAlarm.swift:21
        Row(
            identifier: "emptyReservoir",
            message: "Empty reservoir",
            role: "alertTitle",
            taxonomy: "N4 Reservoir Empty / Out of Insulin",
            taxonomyBucket: "reservoirEmpty",
            expected: .other("Empty reservoir")
        ),
        // DanaKit/Packets/DanaNotifyAlarm.swift:21
        Row(
            identifier: "emptyReservoir",
            message: "Reservoir is empty. Replace it now!",
            role: "alertBody",
            taxonomy: "N4 Reservoir Empty / Out of Insulin",
            taxonomyBucket: "reservoirEmpty",
            expected: .other("Reservoir is empty. Replace it now!")
        ),
        // DanaKit/Packets/DanaNotifyAlarm.swift:22
        Row(
            identifier: "checkShaft",
            message: "Check chaft",
            role: "alertTitle",
            taxonomy: "N1 Hardware Fault / Device Alarm",
            taxonomyBucket: "hardwareFault",
            expected: .other("Check chaft")
        ),
        // DanaKit/Packets/DanaNotifyAlarm.swift:22
        Row(
            identifier: "checkShaft",
            message: "The pump has detected an issue with its chaft. Please remove the reservoir, check everything and try again",
            role: "alertBody",
            taxonomy: "N1 Hardware Fault / Device Alarm",
            taxonomyBucket: "hardwareFault",
            expected: .other(
                "The pump has detected an issue with its chaft. Please remove the reservoir, check everything and try again"
            )
        ),
        // DanaKit/Packets/DanaNotifyAlarm.swift:23
        Row(
            identifier: "basalMax",
            message: "Basal limit reached",
            role: "alertTitle",
            taxonomy: "N2 Delivery Suspended / Stopped",
            taxonomyBucket: "other",
            expected: .other("Basal limit reached")
        ),
        // DanaKit/Packets/DanaNotifyAlarm.swift:23
        Row(
            identifier: "basalMax",
            message: "Your daily basal limit has been reached. Please contact your Dana distributer to increase the limit",
            role: "alertBody",
            taxonomy: "N2 Delivery Suspended / Stopped",
            taxonomyBucket: "other",
            expected: .other(
                "Your daily basal limit has been reached. Please contact your Dana distributer to increase the limit"
            )
        ),
        // DanaKit/Packets/DanaNotifyAlarm.swift:24
        Row(
            identifier: "dailyMax",
            message: "Daily limit reached",
            role: "alertTitle",
            taxonomy: "N2 Delivery Suspended / Stopped",
            taxonomyBucket: "other",
            expected: .other("Daily limit reached")
        ),
        // DanaKit/Packets/DanaNotifyAlarm.swift:24
        Row(
            identifier: "dailyMax",
            message: "Your daily insulin limit has been reached. Please contact your Dana distributer to increase the limit",
            role: "alertBody",
            taxonomy: "N2 Delivery Suspended / Stopped",
            taxonomyBucket: "other",
            expected: .other(
                "Your daily insulin limit has been reached. Please contact your Dana distributer to increase the limit"
            )
        ),
        // DanaKit/Packets/DanaNotifyAlarm.swift:25
        Row(
            identifier: "bloodSugarCheckMiss",
            message: "Missed Blood glucose check",
            role: "alertTitle",
            taxonomy: "N14 Informational / Status",
            taxonomyBucket: "other",
            expected: .other("Missed Blood glucose check")
        ),
        // DanaKit/Packets/DanaNotifyAlarm.swift:25
        Row(
            identifier: "bloodSugarCheckMiss",
            message: "A blood glucose check reminder has been setup in your pump and is triggered. Please remove it or give your glucose level to the pump",
            role: "alertBody",
            taxonomy: "N14 Informational / Status",
            taxonomyBucket: "other",
            expected: .other(
                "A blood glucose check reminder has been setup in your pump and is triggered. Please remove it or give your glucose level to the pump"
            )
        ),
        // DanaKit/Packets/DanaNotifyAlarm.swift:29
        Row(
            identifier: "unknown",
            message: "Unknown error",
            role: "alertTitle",
            taxonomy: "N1 Hardware Fault / Device Alarm",
            taxonomyBucket: "hardwareFault",
            expected: .other("Unknown error")
        ),
        // DanaKit/Packets/DanaNotifyAlarm.swift:29
        Row(
            identifier: "unknown",
            message: "An unknown error has occurred during processing the alert from the pump. Please report this",
            role: "alertBody",
            taxonomy: "N1 Hardware Fault / Device Alarm",
            taxonomyBucket: "hardwareFault",
            expected: .other("An unknown error has occurred during processing the alert from the pump. Please report this")
        ),
        // DanaKit/PumpManager/PumpManagerAlert.swift:18 (dead case, defined copy)
        Row(
            identifier: "ble5InvalidKeys",
            message: "ERROR: Failed to pair device",
            role: "alertTitle",
            taxonomy: "N10 Authentication / Security",
            taxonomyBucket: "other",
            expected: .other("ERROR: Failed to pair device")
        ),
        // DanaKit/PumpManager/PumpManagerAlert.swift:18 (dead case); also ad-hoc DanaKitScanViewModel.swift:77
        Row(
            identifier: "ble5InvalidKeys",
            message: "Failed to pair to <device>. Please go to your bluetooth settings, forget this device, and try again",
            role: "alertBody",
            taxonomy: "N10 Authentication / Security",
            taxonomyBucket: "other",
            expected: .other(
                "Failed to pair to <device>. Please go to your bluetooth settings, forget this device, and try again"
            )
        ),
        // DanaKit/PumpManager/DanaKitPumpManager.swift:641, :894
        Row(
            identifier: "DanaKitPumpManagerError.pumpIsBusy",
            message: "Action has been canceled, because the pump is busy",
            role: "errorMessage",
            taxonomy: "N9 Command / Operation Failure",
            taxonomyBucket: "other",
            expected: .other("Action has been canceled, because the pump is busy")
        ),
        // DanaKit/PumpManager/DanaKitPumpManager.swift:665, :905; DanaBolusStart.swift:56
        Row(
            identifier: "DanaKitPumpManagerError.pumpSuspended",
            message: "The insulin delivery has been suspend. Action failed",
            role: "errorMessage",
            taxonomy: "N9 Command / Operation Failure",
            taxonomyBucket: "other",
            expected: .other("The insulin delivery has been suspend. Action failed")
        ),
        // DanaKit/Packets/DanaBolusStart.swift:58
        Row(
            identifier: "DanaKitPumpManagerError.bolusTimeoutActive",
            message: "A bolus timeout is active. The loop cycle cannot be completed till the timeout is inactive",
            role: "errorMessage",
            taxonomy: "N9 Command / Operation Failure",
            taxonomyBucket: "bolusFailed",
            expected: .commsTransient
        ),
        // DanaKit/Packets/DanaBolusStart.swift:60
        Row(
            identifier: "DanaKitPumpManagerError.bolusMaxViolation",
            message: "The max bolus limit is reached. Please try a lower amount or increase the limit",
            role: "errorMessage",
            taxonomy: "N9 Command / Operation Failure",
            taxonomyBucket: "bolusFailed",
            expected: .other("The max bolus limit is reached. Please try a lower amount or increase the limit")
        ),
        // DanaKit/Packets/DanaBolusStart.swift:62
        Row(
            identifier: "DanaKitPumpManagerError.unknown(bolusCommandError)",
            message: "Unknown error occured: bolusCommandError",
            role: "errorMessage",
            taxonomy: "N9 Command / Operation Failure",
            taxonomyBucket: "bolusFailed",
            expected: .other("Unknown error occured: bolusCommandError")
        ),
        // DanaKit/Packets/DanaBolusStart.swift:64
        Row(
            identifier: "DanaKitPumpManagerError.unknown(Invalid bolus speed error)",
            message: "Unknown error occured: Invalid bolus speed error",
            role: "errorMessage",
            taxonomy: "N9 Command / Operation Failure",
            taxonomyBucket: "bolusFailed",
            expected: .other("Unknown error occured: Invalid bolus speed error")
        ),
        // DanaKit/Packets/DanaBolusStart.swift:66
        Row(
            identifier: "DanaKitPumpManagerError.bolusInsulinLimitViolation",
            message: "The max daily insulin limit is reached. Please try a lower amount or increase the limit",
            role: "errorMessage",
            taxonomy: "N9 Command / Operation Failure",
            taxonomyBucket: "bolusFailed",
            expected: .other("The max daily insulin limit is reached. Please try a lower amount or increase the limit")
        ),
        // DanaKit/Packets/DanaBolusStart.swift:68
        Row(
            identifier: "DanaKitPumpManagerError.unknown(Unknown error: <code>)",
            message: "Unknown error occured: Unknown error: <code>",
            role: "errorMessage",
            taxonomy: "N9 Command / Operation Failure",
            taxonomyBucket: "bolusFailed",
            expected: .other("Unknown error occured: Unknown error: <code>")
        ),
        // DanaKit/PumpManager/DanaKitPumpManager.swift:742, :848, :1101, :1247, :1318, :1416, :1521, :1590
        Row(
            identifier: "DanaKitPumpManagerError.unknown",
            message: "Unknown error occured: <error>",
            role: "errorMessage",
            taxonomy: "N8 Connectivity / Communication",
            taxonomyBucket: "commsTransient",
            expected: .other("Unknown error occured: <error>")
        ),
        // DanaKit/PumpManager/DanaKitPumpManager.swift:750, :795, :1105, :1251, :1322, :1421, :1526, :1594
        Row(
            identifier: "DanaKitPumpManagerError.noConnection",
            message: "Failed to make a connection: <detail>",
            role: "errorMessage",
            taxonomy: "N8 Connectivity / Communication",
            taxonomyBucket: "commsTransient",
            expected: .other("Failed to make a connection: <detail>")
        ),
        // DanaKit/PumpManager/DanaKitPumpManager.swift:811  // NOTE: audit currentCategory was "other"; the verbatim placeholder text contains "communication", so categorize() returns .commsTransient. Pinned to actual behavior.
        Row(
            identifier: "PumpManagerError.communication",
            message: "(no DanaKit-specific message — Loop's generic communication error)",
            role: "errorMessage",
            taxonomy: "N9 Command / Operation Failure",
            taxonomyBucket: "other",
            expected: .commsTransient
        ),
        // DanaKit/PumpManager/DanaKitPumpManager.swift:940
        Row(
            identifier: "DanaKitPumpManagerError.failedTempBasalAdjustment",
            message: "Failed to adjust temp basal. Temp basal below 15 min is unsupported... (floor duration)",
            role: "errorMessage",
            taxonomy: "N9 Command / Operation Failure",
            taxonomyBucket: "other",
            expected: .other("Failed to adjust temp basal. Temp basal below 15 min is unsupported... (floor duration)")
        ),
        // DanaKit/PumpManager/DanaKitPumpManager.swift:959
        Row(
            identifier: "DanaKitPumpManagerError.failedTempBasalAdjustment",
            message: "Failed to adjust temp basal. Basal schedule is not available...",
            role: "errorMessage",
            taxonomy: "N9 Command / Operation Failure",
            taxonomyBucket: "other",
            expected: .other("Failed to adjust temp basal. Basal schedule is not available...")
        ),
        // DanaKit/PumpManager/DanaKitPumpManager.swift:990
        Row(
            identifier: "DanaKitPumpManagerError.failedTempBasalAdjustment",
            message: "Failed to adjust temp basal. Could not cancel old temp basal",
            role: "errorMessage",
            taxonomy: "N9 Command / Operation Failure",
            taxonomyBucket: "other",
            expected: .other("Failed to adjust temp basal. Could not cancel old temp basal")
        ),
        // DanaKit/PumpManager/DanaKitPumpManager.swift:1024
        Row(
            identifier: "DanaKitPumpManagerError.failedTempBasalAdjustment",
            message: "Failed to adjust temp basal. Pump rejected command (15 min)",
            role: "errorMessage",
            taxonomy: "N9 Command / Operation Failure",
            taxonomyBucket: "other",
            expected: .other("Failed to adjust temp basal. Pump rejected command (15 min)")
        ),
        // DanaKit/PumpManager/DanaKitPumpManager.swift:1051
        Row(
            identifier: "DanaKitPumpManagerError.failedTempBasalAdjustment",
            message: "Failed to adjust temp basal. Pump rejected command (30 min)",
            role: "errorMessage",
            taxonomy: "N9 Command / Operation Failure",
            taxonomyBucket: "other",
            expected: .other("Failed to adjust temp basal. Pump rejected command (30 min)")
        ),
        // DanaKit/PumpManager/DanaKitPumpManager.swift:1083
        Row(
            identifier: "DanaKitPumpManagerError.failedTempBasalAdjustment",
            message: "Failed to adjust temp basal. Pump rejected command (full hour)",
            role: "errorMessage",
            taxonomy: "N9 Command / Operation Failure",
            taxonomyBucket: "other",
            expected: .other("Failed to adjust temp basal. Pump rejected command (full hour)")
        ),
        // DanaKit/PumpManager/DanaKitPumpManager.swift:1204, :1281
        Row(
            identifier: "DanaKitPumpManagerError.failedSuspensionAdjustment",
            message: "Failed to adjust suspension",
            role: "errorMessage",
            taxonomy: "N9 Command / Operation Failure",
            taxonomyBucket: "other",
            expected: .other("Failed to adjust suspension")
        ),
        // DanaKit/PumpManager/DanaKitPumpManager.swift:1353, :1367
        Row(
            identifier: "DanaKitPumpManagerError.failedBasalAdjustment",
            message: "Failed to adjust basal",
            role: "errorMessage",
            taxonomy: "N9 Command / Operation Failure",
            taxonomyBucket: "other",
            expected: .other("Failed to adjust basal")
        ),
        // DanaKit/PumpManager/DanaKitPumpManager.swift:1373
        Row(
            identifier: "DanaKitPumpManagerError.failedBasalGeneration",
            message: "Failed to generate Dana basal program",
            role: "errorMessage",
            taxonomy: "N9 Command / Operation Failure",
            taxonomyBucket: "other",
            expected: .other("Failed to generate Dana basal program")
        ),
        // DanaKit/PumpManager/DanaKitPumpManager.swift:1485
        Row(
            identifier: "DanaKitPumpManagerError.unknown(Pump refused to send basal rates back)",
            message: "Unknown error occured: Pump refused to send basal rates back",
            role: "errorMessage",
            taxonomy: "N9 Command / Operation Failure",
            taxonomyBucket: "other",
            expected: .other("Unknown error occured: Pump refused to send basal rates back")
        ),
        // DanaKit/PumpManager/DanaKitPumpManager.swift:1498
        Row(
            identifier: "DanaKitPumpManagerError.unknown(Pump refused to send bolus step back)",
            message: "Unknown error occured: Pump refused to send bolus step back",
            role: "errorMessage",
            taxonomy: "N9 Command / Operation Failure",
            taxonomyBucket: "other",
            expected: .other("Unknown error occured: Pump refused to send bolus step back")
        ),
        // DanaKit/PumpManager/DanaKitPumpManager.swift:1570
        Row(
            identifier: "DanaKitPumpManagerError.failedTimeAdjustment",
            message: "Failed to adjust pump time",
            role: "errorMessage",
            taxonomy: "N9 Command / Operation Failure",
            taxonomyBucket: "other",
            expected: .other("Failed to adjust pump time")
        ),
        // DanaKit/PumpManager/DanaKitPumpManagerError.swift:10 (dead case, defined copy)
        Row(
            identifier: "DanaKitPumpManagerError.unsupportedTempBasal",
            message: "Setting temp basal is not supported at this time. Duration: %lld sec",
            role: "errorMessage",
            taxonomy: "N9 Command / Operation Failure",
            taxonomyBucket: "other",
            expected: .other("Setting temp basal is not supported at this time. Duration: %lld sec")
        ),
        // DanaKit/PumpManager/PeripheralManager.swift:63
        Row(
            identifier: "DanaKitPumpManagerError.unknown(A command is already running)",
            message: "A command is already running",
            role: "errorMessage",
            taxonomy: "N9 Command / Operation Failure",
            taxonomyBucket: "other",
            expected: .other("A command is already running")
        ),
        // DanaKit/Packets/DanaBasalSetProfileRate.swift:11
        Row(
            identifier: "DanaKitPumpManagerError.unknown(Invalid basal rate. Expected length = 24)",
            message: "Invalid basal rate. Expected length = 24",
            role: "errorMessage",
            taxonomy: "N9 Command / Operation Failure",
            taxonomyBucket: "other",
            expected: .other("Invalid basal rate. Expected length = 24")
        ),
        // DanaKit/PumpManager/DanaKitPumpManager.swift:1931 (delegate.pumpManager(_:didError:))
        Row(
            identifier: "PumpManagerError.uncertainDelivery",
            message: "(Loop's standard uncertain-delivery error)",
            role: "errorMessage",
            taxonomy: "N3 Uncertain Delivery / Unacknowledged Command",
            taxonomyBucket: "deliveryUncertain",
            expected: .other("(Loop's standard uncertain-delivery error)")
        ),
        // Common/NotificationHelper.swift:14-22
        Row(
            identifier: "com.bastiaanv.continuous-ble.disconnect-reminder",
            message: "Pump is still disconnected",
            role: "notificationTitle",
            taxonomy: "N8 Connectivity / Communication",
            taxonomyBucket: "commsTransient",
            expected: .other("Pump is still disconnected")
        ),
        // Common/NotificationHelper.swift:14-22
        Row(
            identifier: "com.bastiaanv.continuous-ble.disconnect-reminder",
            message: "Your pump is still disconnected after the set period!",
            role: "notificationBody",
            taxonomy: "N8 Connectivity / Communication",
            taxonomyBucket: "commsTransient",
            expected: .other("Your pump is still disconnected after the set period!")
        ),
        // Common/NotificationHelper.swift:34-42
        Row(
            identifier: "com.bastiaanv.continuous-ble.disconnect-warning",
            message: "Pump is disconnected",
            role: "notificationTitle",
            taxonomy: "N8 Connectivity / Communication",
            taxonomyBucket: "commsTransient",
            expected: .other("Pump is disconnected")
        ),
        // Common/NotificationHelper.swift:34-42
        Row(
            identifier: "com.bastiaanv.continuous-ble.disconnect-warning",
            message: "Your pump is disconnected longer than 5 minutes!",
            role: "notificationBody",
            taxonomy: "N8 Connectivity / Communication",
            taxonomyBucket: "commsTransient",
            expected: .other("Your pump is disconnected longer than 5 minutes!")
        ),
        // DanaKitUI/Views/Onboarding/DanaKitScanView.swift:54-64
        Row(
            identifier: "DanaKitScanView connection-error alert",
            message: "Error while connecting to device",
            role: "alertTitle",
            taxonomy: "N12 Setup / Pairing / Activation",
            taxonomyBucket: "other",
            expected: .other("Error while connecting to device")
        ),
        // DanaKitUI/Views/Onboarding/DanaKitScanView.swift:65-82
        Row(
            identifier: "DanaKitScanView PIN-prompt alert",
            message: "Dana-RS v3 found!",
            role: "alertTitle",
            taxonomy: "N12 Setup / Pairing / Activation",
            taxonomyBucket: "other",
            expected: .other("Dana-RS v3 found!")
        ),
        // DanaKitUI/ViewModels/DanaKitScanViewModel.swift:91
        Row(
            identifier: "connectionErrorMessage (ConnectionResult.timeout)",
            message: "Connection timeout is hit...",
            role: "errorMessage",
            taxonomy: "N12 Setup / Pairing / Activation",
            taxonomyBucket: "other",
            expected: .commsTransient
        ),
        // DanaKitUI/ViewModels/DanaKitScanViewModel.swift:95
        Row(
            identifier: "connectionErrorMessage (ConnectionResult.alreadyConnectedAndBusy)",
            message: "Device is already connected...",
            role: "errorMessage",
            taxonomy: "N12 Setup / Pairing / Activation",
            taxonomyBucket: "other",
            expected: .other("Device is already connected...")
        ),
        // DanaKitUI/Views/Settings/DanaKitRefillReservoirCannula.swift:52
        Row(
            identifier: "failedReservoirAmount label",
            message: "Failed to set reservoir amount. Re-sync pump data and try again please",
            role: "validation",
            taxonomy: "N12 Setup / Pairing / Activation",
            taxonomyBucket: "other",
            expected: .other("Failed to set reservoir amount. Re-sync pump data and try again please")
        ),
        // DanaKitUI/Views/Settings/DanaKitRefillReservoirCannula.swift:96
        Row(
            identifier: "failedTubeAmount label",
            message: "Failed to prime the tube. Please try again later",
            role: "validation",
            taxonomy: "N12 Setup / Pairing / Activation",
            taxonomyBucket: "other",
            expected: .other("Failed to prime the tube. Please try again later")
        ),
        // DanaKitUI/Views/Settings/DanaKitRefillReservoirCannula.swift:149
        Row(
            identifier: "failedPrimeAmount label",
            message: "Failed to prime the cannula. Please try again later",
            role: "validation",
            taxonomy: "N12 Setup / Pairing / Activation",
            taxonomyBucket: "other",
            expected: .other("Failed to prime the cannula. Please try again later")
        ),
        // DanaKitUI/ViewModels/DanaKitScanViewModel.swift:140
        Row(
            identifier: "pinCodePromptError (invalid lengths)",
            message: "Received invalid pincode lengths. Try again",
            role: "validation",
            taxonomy: "N13 Configuration / Validation",
            taxonomyBucket: "other",
            expected: .other("Received invalid pincode lengths. Try again")
        ),
        // DanaKitUI/ViewModels/DanaKitScanViewModel.swift:150
        Row(
            identifier: "pinCodePromptError (invalid hex)",
            message: "Received invalid hex strings. Try again",
            role: "validation",
            taxonomy: "N13 Configuration / Validation",
            taxonomyBucket: "other",
            expected: .other("Received invalid hex strings. Try again")
        ),
        // DanaKitUI/ViewModels/DanaKitScanViewModel.swift:172
        Row(
            identifier: "pinCodePromptError (checksum)",
            message: "Checksum failed. Try again",
            role: "validation",
            taxonomy: "N13 Configuration / Validation",
            taxonomyBucket: "other",
            expected: .other("Checksum failed. Try again")
        ),
        // DanaKit/PumpManager/PeripheralManager.swift:337
        Row(
            identifier: "NSError (Passkey request failed) -> ConnectionResult.failure",
            message: "Passkey request failed",
            role: "errorMessage",
            taxonomy: "N10 Authentication / Security",
            taxonomyBucket: "other",
            expected: .other("Passkey request failed")
        ),
        // DanaKit/PumpManager/PeripheralManager.swift:425
        Row(
            identifier: "NSError (PUMP_CHECK error, wrong serial number) -> ConnectionResult.failure",
            message: "PUMP_CHECK error, wrong serial number",
            role: "errorMessage",
            taxonomy: "N10 Authentication / Security",
            taxonomyBucket: "other",
            expected: .other("PUMP_CHECK error, wrong serial number")
        ),
        // DanaKit/PumpManager/PeripheralManager.swift:453
        Row(
            identifier: "NSError (Invalid password) -> ConnectionResult.failure",
            message: "Invalid password",
            role: "errorMessage",
            taxonomy: "N10 Authentication / Security",
            taxonomyBucket: "other",
            expected: .other("Invalid password")
        ),
        // DanaKit/PumpManager/PeripheralManager.swift:109
        Row(
            identifier: "NSError (Timeout has been hit) -> DanaKitPumpManagerError.unknown",
            message: "Timeout has been hit...",
            role: "errorMessage",
            taxonomy: "N8 Connectivity / Communication",
            taxonomyBucket: "commsTransient",
            expected: .commsTransient
        ),
        // DanaKit/PumpManager/PeripheralManager.swift:140
        Row(
            identifier: "NSError (Failed to discover dana data service) -> ConnectionResult.failure",
            message: "Failed to discover dana data service...",
            role: "errorMessage",
            taxonomy: "N8 Connectivity / Communication",
            taxonomyBucket: "commsTransient",
            expected: .other("Failed to discover dana data service...")
        ),
        // DanaKit/PumpManager/PeripheralManager.swift:161
        Row(
            identifier: "NSError (Failed to discover dana write or read characteristic) -> ConnectionResult.failure",
            message: "Failed to discover dana write or read characteristic",
            role: "errorMessage",
            taxonomy: "N8 Connectivity / Communication",
            taxonomyBucket: "commsTransient",
            expected: .other("Failed to discover dana write or read characteristic")
        ),
        // DanaKit/PumpManager/PeripheralManager.swift:133
        Row(
            identifier: "CoreBluetooth Error (didDiscoverServices) -> ConnectionResult.failure",
            message: "(system error text)",
            role: "errorMessage",
            taxonomy: "N8 Connectivity / Communication",
            taxonomyBucket: "commsTransient",
            expected: .other("(system error text)")
        ),
        // DanaKit/PumpManager/PeripheralManager.swift:151
        Row(
            identifier: "CoreBluetooth Error (didDiscoverCharacteristics) -> ConnectionResult.failure",
            message: "(system error text)",
            role: "errorMessage",
            taxonomy: "N8 Connectivity / Communication",
            taxonomyBucket: "commsTransient",
            expected: .other("(system error text)")
        ),
        // DanaKit/PumpManager/PeripheralManager.swift:172
        Row(
            identifier: "CoreBluetooth Error (notify enable failed) -> ConnectionResult.failure",
            message: "(system error text)",
            role: "errorMessage",
            taxonomy: "N8 Connectivity / Communication",
            taxonomyBucket: "commsTransient",
            expected: .other("(system error text)")
        ),
        // DanaKit/PumpManager/PeripheralManager.swift:183
        Row(
            identifier: "CoreBluetooth Error (didUpdateValueFor) -> ConnectionResult.failure",
            message: "(system error text)",
            role: "errorMessage",
            taxonomy: "N8 Connectivity / Communication",
            taxonomyBucket: "commsTransient",
            expected: .other("(system error text)")
        ),
        // DanaKit/PumpManager/PeripheralManager.swift:381, :392
        Row(
            identifier: "NSError (Invalid hwModel) -> ConnectionResult.failure",
            message: "Invalid hwModel",
            role: "errorMessage",
            taxonomy: "N8 Connectivity / Communication",
            taxonomyBucket: "commsTransient",
            expected: .other("Invalid hwModel")
        ),
        // DanaKit/PumpManager/PeripheralManager.swift:419
        Row(
            identifier: "NSError (PUMP_CHECK error) -> ConnectionResult.failure",
            message: "PUMP_CHECK error",
            role: "errorMessage",
            taxonomy: "N8 Connectivity / Communication",
            taxonomyBucket: "commsTransient",
            expected: .other("PUMP_CHECK error")
        ),
        // DanaKit/PumpManager/PeripheralManager.swift:422
        Row(
            identifier: "NSError (PUMP_CHECK_BUSY error) -> ConnectionResult.failure",
            message: "PUMP_CHECK_BUSY error",
            role: "errorMessage",
            taxonomy: "N8 Connectivity / Communication",
            taxonomyBucket: "commsTransient",
            expected: .other("PUMP_CHECK_BUSY error")
        ),
        // DanaKit/PumpManager/BluetoothManager.swift:53
        Row(
            identifier: "NSError (Invalid bluetooth state) -> startScan throw",
            message: "Invalid bluetooth state - state: <n>",
            role: "errorMessage",
            taxonomy: "N8 Connectivity / Communication",
            taxonomyBucket: "commsTransient",
            expected: .other("Invalid bluetooth state - state: <n>")
        ),
        // DanaKit/PumpManager/BluetoothManager.swift:77
        Row(
            identifier: "NSError (Invalid identifier) -> connect throw",
            message: "Invalid identifier - <id>",
            role: "errorMessage",
            taxonomy: "N8 Connectivity / Communication",
            taxonomyBucket: "commsTransient",
            expected: .other("Invalid identifier - <id>")
        ),
        // DanaKit/PumpManager/BluetoothManager.swift:124; ContinousBluetoothManager.swift:73; InteractiveBluetoothManager.swift:182
        Row(
            identifier: "NSError (No connected device) -> finishV3Pairing throw",
            message: "No connected device",
            role: "errorMessage",
            taxonomy: "N8 Connectivity / Communication",
            taxonomyBucket: "commsTransient",
            expected: .other("No connected device")
        ),
        // DanaKit/PumpManager/BluetoothManager.swift:237
        Row(
            identifier: "NSError (No pumpManager) -> ConnectionResult.failure",
            message: "No pumpManager",
            role: "errorMessage",
            taxonomy: "N8 Connectivity / Communication",
            taxonomyBucket: "commsTransient",
            expected: .other("No pumpManager")
        ),
        // DanaKit/PumpManager/ContinousBluetoothManager.swift:147
        Row(
            identifier: "NSError (Couldn't reconnect) -> noConnection",
            message: "Couldn't reconnect",
            role: "errorMessage",
            taxonomy: "N8 Connectivity / Communication",
            taxonomyBucket: "commsTransient",
            expected: .other("Couldn't reconnect")
        ),
        // DanaKit/PumpManager/ContinousBluetoothManager.swift:165
        Row(
            identifier: "NSError (Device is forced disconnected) -> noConnection",
            message: "Device is forced disconnected...",
            role: "errorMessage",
            taxonomy: "N8 Connectivity / Communication",
            taxonomyBucket: "commsTransient",
            expected: .other("Device is forced disconnected...")
        ),
        // DanaKit/PumpManager/InteractiveBluetoothManager.swift:158
        Row(
            identifier: "NSError (Pump is not onboarded) -> noConnection",
            message: "Pump is not onboarded",
            role: "errorMessage",
            taxonomy: "N8 Connectivity / Communication",
            taxonomyBucket: "commsTransient",
            expected: .other("Pump is not onboarded")
        )
    ]

    // MARK: - Classification pinned to CURRENT (must be green)

    @Test(
        "each (identifier, message) classifies as pinned",
        arguments: rows
    ) func classificationPinned(_ row: Row) {
        // Feeds the EXACT display string through StubError so the substring
        // classifier matches over the real text, and pins the category it
        // returns today. Almost all DanaKit prose -> .other(message).
        #expect(
            TrioAlertClassifier.categorize(error: StubError(description: row.message)) == row.expected
        )
    }

    // MARK: - Classifier coverage gaps (ratchet)

    /// "identifier — message" keys for emissions that the substring classifier
    /// drops to `.other` even though the taxonomy implies a real, mappable
    /// bucket. The classifier SHOULD route each below, but the natural-language
    /// text lacks the concatenated token it scans for. Per gap, the bucket it
    /// should hit and why the tokens miss:
    ///
    ///  - N1 Hardware Fault -> `.hardwareFault` (token "fault"): "Pump error",
    ///    "Check the pump and try again", "Check chaft", "The pump has detected
    ///    an issue with its chaft...", "Unknown error", "An unknown error has
    ///    occurred...". None contains "fault".
    ///    Source: DanaKit/Packets/DanaNotifyAlarm.swift:12, :22, :29
    ///  - N1 occlusion BODY -> `.occlusion` (token "occlusion"): "Check the
    ///    reservoir and infus and try again" — the title matches, the body does
    ///    not contain "occlusion".
    ///    Source: DanaKit/Packets/DanaNotifyAlarm.swift:13
    ///  - F1 Insulin Supply Low -> `.reservoirLow` (token "lowreservoir"):
    ///    "Remaining insulin level" does not contain "lowreservoir".
    ///    Source: DanaKit/Packets/DanaNotifyAlarm.swift:19
    ///  - N4 Reservoir Empty -> `.reservoirEmpty` (tokens "reservoirempty"/
    ///    "emptyreservoir"): "Empty reservoir" and "Reservoir is empty. Replace
    ///    it now!" both break the token across a space.
    ///    Source: DanaKit/Packets/DanaNotifyAlarm.swift:21
    ///  - N9 bolus-failure copy -> `.bolusFailed` (token "bolusfailed"): the
    ///    max-bolus/insulin-limit and bolus "Unknown error occured: ..." strings
    ///    never contain "bolusfailed".
    ///    Source: DanaKit/Packets/DanaBolusStart.swift:60, :62, :64, :66, :68
    ///  - N8 connectivity copy -> `.commsTransient` (tokens "communication"/
    ///    "comms"/"timeout"/"notconnected"/...): the generic
    ///    "Unknown error occured: <error>", "Failed to make a connection:
    ///    <detail>", disconnect notifications, CoreBluetooth/NSError discovery
    ///    and PUMP_CHECK / bluetooth-state strings lack any of the literal
    ///    tokens.
    ///    Source: DanaKit/PumpManager/DanaKitPumpManager.swift:742...;
    ///    Common/NotificationHelper.swift:14-22, :34-42;
    ///    DanaKit/PumpManager/PeripheralManager.swift:133, :140, :151, :161,
    ///    :172, :183, :381, :419, :422; BluetoothManager.swift:53, :77, :124,
    ///    :237; ContinousBluetoothManager.swift:147, :165;
    ///    InteractiveBluetoothManager.swift:158
    ///  - N3 Uncertain Delivery -> `.deliveryUncertain` (tokens
    ///    "uncertaindelivery"/"unacknowledged"/"bolus may have failed"): the
    ///    catalogued placeholder for Loop's standard uncertain-delivery error
    ///    contains none of these literal tokens.
    ///    Source: DanaKit/PumpManager/DanaKitPumpManager.swift:1931
    ///
    /// NOT captured by this ratchet (already classifies as a non-`.other`
    /// bucket, but the WRONG one): "A bolus timeout is active..." (bolusFailed
    /// taxonomy) contains "timeout" so it routes to `.commsTransient`, not
    /// `.bolusFailed`. It is a real gap in the audit but the recompute below
    /// only catches `.other` drops (expected == .other while bucket != other),
    /// so it is documented here rather than listed.
    /// Source: DanaKit/Packets/DanaBolusStart.swift:58
    ///
    /// Stays green now; FAILS (forcing this file to be updated) when the
    /// classifier improves and one of these strings starts mapping.
    static let classifierCoverageGaps: Set<String> = [
        "pumpError — Pump error",
        "pumpError — Check the pump and try again",
        "occlusion — Check the reservoir and infus and try again",
        "remainingInsulinLevel — Remaining insulin level",
        "emptyReservoir — Empty reservoir",
        "emptyReservoir — Reservoir is empty. Replace it now!",
        "checkShaft — Check chaft",
        "checkShaft — The pump has detected an issue with its chaft. Please remove the reservoir, check everything and try again",
        "unknown — Unknown error",
        "unknown — An unknown error has occurred during processing the alert from the pump. Please report this",
        "DanaKitPumpManagerError.bolusMaxViolation — The max bolus limit is reached. Please try a lower amount or increase the limit",
        "DanaKitPumpManagerError.unknown(bolusCommandError) — Unknown error occured: bolusCommandError",
        "DanaKitPumpManagerError.unknown(Invalid bolus speed error) — Unknown error occured: Invalid bolus speed error",
        "DanaKitPumpManagerError.bolusInsulinLimitViolation — The max daily insulin limit is reached. Please try a lower amount or increase the limit",
        "DanaKitPumpManagerError.unknown(Unknown error: <code>) — Unknown error occured: Unknown error: <code>",
        "DanaKitPumpManagerError.unknown — Unknown error occured: <error>",
        "DanaKitPumpManagerError.noConnection — Failed to make a connection: <detail>",
        "PumpManagerError.uncertainDelivery — (Loop's standard uncertain-delivery error)",
        "com.bastiaanv.continuous-ble.disconnect-reminder — Pump is still disconnected",
        "com.bastiaanv.continuous-ble.disconnect-reminder — Your pump is still disconnected after the set period!",
        "com.bastiaanv.continuous-ble.disconnect-warning — Pump is disconnected",
        "com.bastiaanv.continuous-ble.disconnect-warning — Your pump is disconnected longer than 5 minutes!",
        "NSError (Failed to discover dana data service) -> ConnectionResult.failure — Failed to discover dana data service...",
        "NSError (Failed to discover dana write or read characteristic) -> ConnectionResult.failure — Failed to discover dana write or read characteristic",
        "CoreBluetooth Error (didDiscoverServices) -> ConnectionResult.failure — (system error text)",
        "CoreBluetooth Error (didDiscoverCharacteristics) -> ConnectionResult.failure — (system error text)",
        "CoreBluetooth Error (notify enable failed) -> ConnectionResult.failure — (system error text)",
        "CoreBluetooth Error (didUpdateValueFor) -> ConnectionResult.failure — (system error text)",
        "NSError (Invalid hwModel) -> ConnectionResult.failure — Invalid hwModel",
        "NSError (PUMP_CHECK error) -> ConnectionResult.failure — PUMP_CHECK error",
        "NSError (PUMP_CHECK_BUSY error) -> ConnectionResult.failure — PUMP_CHECK_BUSY error",
        "NSError (Invalid bluetooth state) -> startScan throw — Invalid bluetooth state - state: <n>",
        "NSError (Invalid identifier) -> connect throw — Invalid identifier - <id>",
        "NSError (No connected device) -> finishV3Pairing throw — No connected device",
        "NSError (No pumpManager) -> ConnectionResult.failure — No pumpManager",
        "NSError (Couldn't reconnect) -> noConnection — Couldn't reconnect",
        "NSError (Device is forced disconnected) -> noConnection — Device is forced disconnected...",
        "NSError (Pump is not onboarded) -> noConnection — Pump is not onboarded"
    ]

    @Test("classifier coverage gaps are exactly as documented") func classifierCoverageGapsExact() {
        // A gap is an emission the classifier drops to .other while its
        // taxonomy bucket is non-other. Recompute from rows independently of
        // the pinned set: expected == .other(message) AND taxonomyBucket is not
        // "other". If a string starts matching a real token its expected leaves
        // .other and it drops out of `computed`, breaking this equality and
        // forcing an update here.
        let computed: Set<String> = Set(
            Self.rows.compactMap { row -> String? in
                guard case .other = row.expected, row.taxonomyBucket != "other" else { return nil }
                return "\(row.identifier) — \(row.message)"
            }
        )
        #expect(computed == Self.classifierCoverageGaps)
    }
}
