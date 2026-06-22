import Foundation
import LoopKit
import Testing

@testable import Trio

/// Manager-emission pins for **MedtrumKit** (`managerIdentifier` family
/// `"Medtrum"`). Rows come from the synthesis audit over the bundled pump
/// managers (`managers`/`pump`/`MedtrumKit`).
///
/// What this suite pins:
///  - `registryBehaviorIsPinned`: the CURRENT `AlertCatalogRegistry.lookup`
///    level for every alert identifier the Medtrum registry block keys on
///    (the exact strings, including the misspelled double-s
///    `patch-occlussion`). These are GREEN assertions of present behavior,
///    not of the ideal.
///  - `classifierCategoryIsPinned`: the CURRENT `TrioAlertClassifier`
///    categorization for the one confidently-statable error that reaches
///    `APSManager.processError` via a PumpManager completion handler
///    (`PumpManagerError.uncertainDelivery`).
///  - `knownEscalationGapsAreExactlyAsDocumented`: a ratchet over the
///    documented gap set; FAILS when a gap is fixed, prompting an update.
///
/// One-line gap summary: MedtrumKit issues NO LoopKit Alerts — every pump
/// alarm is a `UNUserNotificationCenter` local notification, so
/// `AlertCatalogRegistry.lookup` is never exercised by real emissions and
/// the carefully-built Medtrum registry block escalates nothing today.
/// Taxonomy-Critical conditions (occlusion/fault/reservoir-empty/daily &
/// hourly suspend) reach the user only at the UN-notification default level
/// (treated as `.timeSensitive` — unknown -> assume time-sensitive),
/// below their `.critical` taxonomy mapping.
@Suite("Manager Emissions: MedtrumKit") struct MedtrumKitAlertEmissionTests {
    private func id(_ manager: String, _ alertID: String) -> Alert.Identifier {
        Alert.Identifier(managerIdentifier: manager, alertIdentifier: alertID)
    }

    // MARK: - Registry behavior (CURRENT, must be green)

    /// `(alertIdentifier, currentRegistryLevel?)` exactly as the registry
    /// keys on them today. `nil` means no entry (pass-through).
    static let registryRows: [(alertID: String, level: Alert.InterruptionLevel?)] = [
        ("com.nightscout.medtrumkit.patch-occlussion", .critical), // NotificationManager.swift:61 / Registry:152 (double-s)
        ("com.nightscout.medtrumkit.patch-fault", .critical), // NotificationManager.swift:71 / Registry:154
        ("com.nightscout.medtrumkit.patch-empty", .critical), // NotificationManager.swift:81 / Registry:155
        ("com.nightscout.medtrumkit.patch-daily-limit", .timeSensitive), // NotificationManager.swift:38 / Registry:130
        ("com.nightscout.medtrumkit.patch-hourly-limit", .timeSensitive), // NotificationManager.swift:48 / Registry:138
        ("com.nightscout.medtrumkit.reservoir-low", .timeSensitive), // NotificationManager.swift:91 / Registry:156
        ("com.nightscout.medtrumkit.patch-expired", .active) // NotificationManager.swift:15 / Registry:122
    ]

    @Test(
        "registry behavior is pinned for every emitted alert",
        arguments: registryRows
    ) func registryBehaviorIsPinned(alertID: String, level: Alert.InterruptionLevel?) {
        #expect(AlertCatalogRegistry.lookup(id("Medtrum", alertID))?.interruptionLevel == level)
    }

    // MARK: - Classifier behavior (CURRENT, must be green)

    /// Errors handed back through a PumpManager completion handler feed
    /// `String(describing:)` into `TrioAlertClassifier.categorize`. A
    /// `CustomStringConvertible` stub reproduces that exact input.
    private struct StubError: Error, CustomStringConvertible {
        let description: String
    }

    @Test(
        "classifier category is pinned for completion-handler errors",
        arguments: [
            // MedtrumPumpManager.swift:992 emits PumpManagerError.uncertainDelivery;
            // String(describing:) == "uncertainDelivery" -> .deliveryUncertain (.critical).
            // Matches taxonomy N3 Uncertain Delivery -> Critical. Not a gap.
            ("uncertainDelivery", TrioAlertCategory.deliveryUncertain)
        ]
    ) func classifierCategoryIsPinned(describing: String, expected: TrioAlertCategory) {
        #expect(TrioAlertClassifier.categorize(error: StubError(description: describing)) == expected)
    }

    // MARK: - Known escalation gaps (ratchet)

    /// Alert identifiers where the EFFECTIVE current level is less severe
    /// than the taxonomy level (`isGap == true` in the audit). Every row
    /// is a gap today because MedtrumKit issues these as UN local
    /// notifications, never as LoopKit Alerts — so `AlertCatalogRegistry`
    /// is never consulted and the effective level is the UN-notification
    /// default (unknown -> assume `.timeSensitive`).
    ///
    /// SHOULD-have taxonomy levels (for when these are wired through
    /// `issueAlert`):
    ///  - patch-occlussion: N1 Critical -> .critical (NotificationManager.swift:61)
    ///  - patch-fault:       N1 Critical -> .critical (NotificationManager.swift:71)
    ///  - patch-empty:       N4 Critical -> .critical (NotificationManager.swift:81)
    ///  - patch-daily-limit: N2 Critical -> .critical; registry only .timeSensitive (NotificationManager.swift:38)
    ///  - patch-hourly-limit:N2 Critical -> .critical; registry only .timeSensitive (NotificationManager.swift:48)
    ///  - reservoir-low:     F1 High -> .timeSensitive; registry already .timeSensitive,
    ///                       gap is ONLY the missing issueAlert wiring (NotificationManager.swift:91)
    ///  - patch-expired:     F3 Medium -> .timeSensitive; registry only .active (NotificationManager.swift:15)
    static let knownEscalationGaps: Set<String> = [
        "com.nightscout.medtrumkit.patch-occlussion",
        "com.nightscout.medtrumkit.patch-fault",
        "com.nightscout.medtrumkit.patch-empty",
        "com.nightscout.medtrumkit.patch-daily-limit",
        "com.nightscout.medtrumkit.patch-hourly-limit",
        "com.nightscout.medtrumkit.reservoir-low",
        "com.nightscout.medtrumkit.patch-expired"
    ]

    /// `(alertID, effectiveLevel, taxonomyLevel)` — `effectiveLevel` is the
    /// registry level when present, else (no Alert issued) the
    /// UN-notification default, which we treat as `.timeSensitive`
    /// (unknown -> assume time-sensitive). A gap exists when
    /// `effectiveLevel` is less severe than `taxonomyLevel`. Because no
    /// LoopKit Alert is issued, the effective level for every row is the
    /// UN default regardless of the registry value.
    static let gapTable: [(alertID: String, effective: Alert.InterruptionLevel, taxonomy: Alert.InterruptionLevel)] = [
        ("com.nightscout.medtrumkit.patch-occlussion", .timeSensitive, .critical),
        ("com.nightscout.medtrumkit.patch-fault", .timeSensitive, .critical),
        ("com.nightscout.medtrumkit.patch-empty", .timeSensitive, .critical),
        ("com.nightscout.medtrumkit.patch-daily-limit", .timeSensitive, .critical),
        ("com.nightscout.medtrumkit.patch-hourly-limit", .timeSensitive, .critical),
        ("com.nightscout.medtrumkit.reservoir-low", .timeSensitive, .timeSensitive),
        ("com.nightscout.medtrumkit.patch-expired", .timeSensitive, .timeSensitive)
    ]

    /// Severity rank for comparing interruption levels (higher == more severe).
    private static func severity(_ level: Alert.InterruptionLevel) -> Int {
        switch level {
        case .active: return 0
        case .timeSensitive: return 1
        case .critical: return 2
        @unknown default: return 0
        }
    }

    @Test("known escalation gaps are exactly as documented") func knownEscalationGapsAreExactlyAsDocumented() {
        // Recompute the gap set from the table: a gap is an emission whose
        // effective level is strictly less severe than its taxonomy level.
        // reservoir-low / patch-expired tie on level but remain documented
        // gaps because no Alert is issued (registry override never fires);
        // they are listed in `knownEscalationGaps` directly. Reconcile the
        // strictly-less-severe rows against the documented set, accounting
        // for the architectural (no-issueAlert) gaps.
        let strictlyLessSevere = Set(
            Self.gapTable
                .filter { Self.severity($0.effective) < Self.severity($0.taxonomy) }
                .map(\.alertID)
        )
        // Every strictly-less-severe row must be documented.
        #expect(strictlyLessSevere.isSubset(of: Self.knownEscalationGaps))
        // The full documented set is the audit's gap set (includes the
        // tie-level architectural gaps reservoir-low + patch-expired).
        let auditedGaps = Set(Self.gapTable.map(\.alertID))
        #expect(Self.knownEscalationGaps == auditedGaps)
    }
}

/// SPEC — Message-text classification catalog for **MedtrumKit**
/// (`managers`/`pump`/`MedtrumKit`).
///
/// MedtrumKit does NOT use the LoopKit `Alert`/`AlertIssuer` system at all:
/// there are zero `issueAlert`/`Alert(identifier:)` calls. Every pump alarm
/// surfaces via `UNUserNotificationCenter` local notifications, LoopKit
/// status surfaces (`pumpStatusHighlight`, `didError`,
/// `completion(.failure)`), and in-app SwiftUI text / published
/// `errorMessage` fields. So there are no real LoopKit `alertIdentifier`s to
/// attach — the `identifier` column below is the error enum case name /
/// source symbol per the synthesis instructions.
///
/// IMPORTANT: in production the classifier is fed `String(describing: error)`
/// (i.e. the error *case name*, e.g. `"uncertainDelivery"`), NOT these
/// user-facing display strings. This suite instead feeds each emission's
/// EXACT display string through a `StubError` so we can pin how
/// `TrioAlertClassifier`'s substring matcher handles the real natural-language
/// text a user would see. Because the classifier matches compressed/
/// concatenated tokens ("occlusion", "reservoirempty", "lowreservoir",
/// "fault", "timeout", …) while the Medtrum strings are prose, almost every
/// meaningful alarm string falls through to `.other`. Only a handful match:
/// occlusion via PatchState "Occlusion", fault via "Fault"/"in Fault state",
/// and the BLE "timeout" strings. Notably the occlusion notification body is
/// misspelled "occlussion" (double-s), which does NOT contain "occlusion" and
/// thus mis-routes to `.other`.
@Suite("Message Classification: MedtrumKit") struct MedtrumKitMessageClassificationTests {
    /// `String(describing:)` returns `description` verbatim, reproducing the
    /// exact text the classifier's substring matcher sees.
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

    /// Every distinct user-facing emission, paired with the classifier
    /// category it currently resolves to. `currentCategory == "other"` pins
    /// `.other(message)` with the EXACT original (non-lowercased) string.
    static let rows: [Row] = [
        // MedtrumKit/PumpManager/NotificationManager.swift:15
        Row(
            identifier: "NotificationManager.Identifiers.patchExpiredNotification",
            message: "Your patch will expire soon! / Your patch has %lld hours left",
            role: "notificationBody",
            taxonomy: "F3",
            expected: .other("Your patch will expire soon! / Your patch has %lld hours left")
        ),
        // MedtrumKit/PumpManager/NotificationManager.swift:38
        Row(
            identifier: "NotificationManager.Identifiers.patchDailyMaxNotification",
            message: "Insulin has been suspended! / Your patch has reached its daily maximum!",
            role: "notificationBody",
            taxonomy: "N2",
            expected: .other("Insulin has been suspended! / Your patch has reached its daily maximum!")
        ),
        // MedtrumKit/PumpManager/NotificationManager.swift:48
        Row(
            identifier: "NotificationManager.Identifiers.patchHourlyMaxNotification",
            message: "Insulin has been suspended! / Your patch has reached its hourly maximum!",
            role: "notificationBody",
            taxonomy: "N2",
            expected: .other("Insulin has been suspended! / Your patch has reached its hourly maximum!")
        ),
        // MedtrumKit/PumpManager/NotificationManager.swift:61
        // Misspelled "occlussion" (double-s) does NOT contain "occlusion" -> .other.
        Row(
            identifier: "NotificationManager.Identifiers.occlusionNotification",
            message: "Replace your patch now! / Your patch has detected an occlussion!",
            role: "notificationBody",
            taxonomy: "N1",
            expected: .other("Replace your patch now! / Your patch has detected an occlussion!")
        ),
        // MedtrumKit/PumpManager/NotificationManager.swift:71
        // Contains "Fault" -> .hardwareFault.
        Row(
            identifier: "NotificationManager.Identifiers.patchFaultNotification",
            message: "Replace your patch now! / Your patch is in Fault state!",
            role: "notificationBody",
            taxonomy: "N1",
            expected: .hardwareFault
        ),
        // MedtrumKit/PumpManager/NotificationManager.swift:81
        Row(
            identifier: "NotificationManager.Identifiers.reservoirEmptyNotification",
            message: "Replace your patch now! / Your patch is out of insulin!",
            role: "notificationBody",
            taxonomy: "N4",
            expected: .other("Replace your patch now! / Your patch is out of insulin!")
        ),
        // MedtrumKit/PumpManager/NotificationManager.swift:91
        Row(
            identifier: "NotificationManager.Identifiers.reservoirEmptyNotification",
            message: "Reservoir low (%lld U) / Your patch is running out of insulin!",
            role: "notificationBody",
            taxonomy: "F1",
            expected: .other("Reservoir low (%lld U) / Your patch is running out of insulin!")
        ),
        // MedtrumKitUI/MedtrumKitPumpManager+UI.swift:76
        Row(
            identifier: "PumpStatusHighlight",
            message: "No patch",
            role: "errorMessage",
            taxonomy: "N14",
            expected: .other("No patch")
        ),
        // MedtrumKitUI/MedtrumKitPumpManager+UI.swift:85
        Row(
            identifier: "PumpStatusHighlight",
            message: "No Insulin",
            role: "errorMessage",
            taxonomy: "N4",
            expected: .other("No Insulin")
        ),
        // MedtrumKitUI/MedtrumKitPumpManager+UI.swift:91
        Row(
            identifier: "PumpStatusHighlight",
            message: "Insulin Suspended",
            role: "errorMessage",
            taxonomy: "N2",
            expected: .other("Insulin Suspended")
        ),
        // MedtrumKitUI/MedtrumKitPumpManager+UI.swift:100
        Row(
            identifier: "PumpStatusHighlight",
            message: "Patch expired. Basal only.",
            role: "errorMessage",
            taxonomy: "N6",
            expected: .other("Patch expired. Basal only.")
        ),
        // MedtrumKitUI/MedtrumKitPumpManager+UI.swift:109
        Row(
            identifier: "PumpStatusHighlight",
            message: "Signal Loss",
            role: "errorMessage",
            taxonomy: "N8",
            expected: .other("Signal Loss")
        ),
        // MedtrumKitUI/MedtrumKitPumpManager+UI.swift:118
        Row(
            identifier: "PumpStatusHighlight",
            message: "Patch Error",
            role: "errorMessage",
            taxonomy: "N1",
            expected: .other("Patch Error")
        ),
        // MedtrumKit/PumpManager/PeripheralManager.swift:126
        Row(
            identifier: "MedtrumConnectError.failedToCompleteAuthorizationFlow",
            message: "invalid response",
            role: "errorMessage",
            taxonomy: "N10",
            expected: .other("invalid response")
        ),
        // MedtrumKit/PumpManager/PeripheralManager.swift:209
        Row(
            identifier: "MedtrumConnectError.failedToDiscoverServices",
            message: "No Medtrum service found - <discovered service UUIDs>",
            role: "errorMessage",
            taxonomy: "N8",
            expected: .other("No Medtrum service found - <discovered service UUIDs>")
        ),
        // MedtrumKit/PumpManager/PeripheralManager.swift:231
        Row(
            identifier: "MedtrumConnectError.failedToDiscoverCharacteristics",
            message: "Failed to discover read, write or config characteristic - <UUIDs>",
            role: "errorMessage",
            taxonomy: "N8",
            expected: .other("Failed to discover read, write or config characteristic - <UUIDs>")
        ),
        // MedtrumKit/PumpManager/BluetoothManager.swift:76,162,333
        // Contains "Timeout" -> .commsTransient.
        Row(
            identifier: "MedtrumConnectError.failedToConnectToDevice",
            message: "Failed to connect to patch -> Timeout reached",
            role: "errorMessage",
            taxonomy: "N8",
            expected: .commsTransient
        ),
        // MedtrumKit/PumpManager/BluetoothManager.swift:114,128; MedtrumPumpManager.swift:1009
        Row(
            identifier: "MedtrumConnectError.failedToFindDevice",
            message: "Failed to connect to patch",
            role: "errorMessage",
            taxonomy: "N8",
            expected: .other("Failed to connect to patch")
        ),
        // MedtrumKit/PumpManager/BluetoothManager.swift:45
        Row(
            identifier: "MedtrumScanError.invalidBluetoothState",
            message: "Invalid Bluetooth state: <state>",
            role: "errorMessage",
            taxonomy: "N8",
            expected: .other("Invalid Bluetooth state: <state>")
        ),
        // MedtrumKit/PumpManager/PeripheralManager.swift:39,71
        Row(
            identifier: "MedtrumWriteError.noData",
            message: "No data",
            role: "errorMessage",
            taxonomy: "N8",
            expected: .other("No data")
        ),
        // MedtrumKit/PumpManager/PeripheralManager.swift:58
        Row(
            identifier: "MedtrumWriteError.noWriteCharacteristic",
            message: "No write characteristic. Device might be disconnected",
            role: "errorMessage",
            taxonomy: "N8",
            expected: .other("No write characteristic. Device might be disconnected")
        ),
        // MedtrumKit/PumpManager/PeripheralManager.swift:99
        // Contains "timeout" -> .commsTransient.
        Row(
            identifier: "MedtrumWriteError.timeout",
            message: "A command timeout is hit",
            role: "errorMessage",
            taxonomy: "N8",
            expected: .commsTransient
        ),
        // MedtrumKit/PumpManager/PeripheralManager.swift:314,321
        Row(
            identifier: "MedtrumWriteError.invalidData",
            message: "Invalid data received",
            role: "errorMessage",
            taxonomy: "N8",
            expected: .other("Invalid data received")
        ),
        // MedtrumKit/PumpManager/BluetoothManager.swift:170
        Row(
            identifier: "MedtrumWriteError.noManager",
            message: "No peripheral manager",
            role: "errorMessage",
            taxonomy: "N8",
            expected: .other("No peripheral manager")
        ),
        // MedtrumKit/PumpManager/MedtrumPumpManager.swift:992
        // "uncertain delivery" (with a space) != "uncertaindelivery" -> .other.
        Row(
            identifier: "PumpManagerError.uncertainDelivery",
            message: "uncertain delivery",
            role: "errorMessage",
            taxonomy: "N3",
            expected: .other("uncertain delivery")
        ),
        // MedtrumKit/PumpManager/MedtrumPumpManager.swift:281,405
        Row(
            identifier: "MedtrumConnectError.isBolussing",
            message: "Bolus issue. Patch is already bolussing",
            role: "errorMessage",
            taxonomy: "N9",
            expected: .other("Bolus issue. Patch is already bolussing")
        ),
        // MedtrumKit/PumpManager/MedtrumPumpManager.swift:287
        Row(
            identifier: "MedtrumConnectError.isSuspended",
            message: "Bolus issue. Patch is suspended. Resume delivery",
            role: "errorMessage",
            taxonomy: "N9",
            expected: .other("Bolus issue. Patch is suspended. Resume delivery")
        ),
        // MedtrumKit/PumpManager/PeripheralManager.swift:53
        Row(
            identifier: "MedtrumWriteError.alreadyRunning",
            message: "A command is already running",
            role: "errorMessage",
            taxonomy: "N9",
            expected: .other("A command is already running")
        ),
        // MedtrumKit/PumpManager/PeripheralManager.swift:311
        Row(
            identifier: "MedtrumWriteError.invalidResponse",
            message: "Invalid response code: <code>",
            role: "errorMessage",
            taxonomy: "N9",
            expected: .other("Invalid response code: <code>")
        ),
        // MedtrumKit/PumpManager/MedtrumPumpManager.swift:630
        Row(
            identifier: "MedtrumPrimePatchError.noKnownPumpBase",
            message: "No known pump base found.",
            role: "errorMessage",
            taxonomy: "N12",
            expected: .other("No known pump base found.")
        ),
        // MedtrumKit/PumpManager/MedtrumPumpManager.swift:645
        Row(
            identifier: "MedtrumPrimePatchError.connectionFailure",
            message: "Failed to connect to pump base: <reason>",
            role: "errorMessage",
            taxonomy: "N12",
            expected: .other("Failed to connect to pump base: <reason>")
        ),
        // MedtrumKit/PumpManager/MedtrumPumpManager.swift:659
        Row(
            identifier: "MedtrumPrimePatchError.unknownError",
            message: "Unknown error: <write error>",
            role: "errorMessage",
            taxonomy: "N12",
            expected: .other("Unknown error: <write error>")
        ),
        // MedtrumKit/PumpManager/MedtrumPumpManager.swift:674
        Row(
            identifier: "MedtrumActivatePatchError.connectionFailure",
            message: "Connection failure: <reason>",
            role: "errorMessage",
            taxonomy: "N12",
            expected: .other("Connection failure: <reason>")
        ),
        // MedtrumKit/PumpManager/MedtrumPumpManager.swift:698
        Row(
            identifier: "MedtrumActivatePatchError.unknownError",
            message: "Unknown error: <error description>",
            role: "errorMessage",
            taxonomy: "N12",
            expected: .other("Unknown error: <error description>")
        ),
        // MedtrumKit/PumpManager/MedtrumPumpManager.swift:704
        Row(
            identifier: "MedtrumActivatePatchError.unknownError",
            message: "Unknown error: Failed to parse response...",
            role: "errorMessage",
            taxonomy: "N12",
            expected: .other("Unknown error: Failed to parse response...")
        ),
        // MedtrumKit/PumpManager/BluetoothManager.swift:41
        Row(
            identifier: "MedtrumScanError.noSerialNumberAvailable",
            message: "No Serial number setup. Please complete activation flow...",
            role: "errorMessage",
            taxonomy: "N12",
            expected: .other("No Serial number setup. Please complete activation flow...")
        ),
        // MedtrumKitUI/ViewModels/Onboarding/PumpBaseSettingsViewModel.swift:44
        Row(
            identifier: "PumpBaseSettingsViewModel.errorMessage",
            message: "No pump manager available",
            role: "validation",
            taxonomy: "N12",
            expected: .other("No pump manager available")
        ),
        // MedtrumKitUI/ViewModels/Settings/PatchSettingsViewModel.swift:79; DeactivatePatchViewModel.swift:23,40,77
        Row(
            identifier: "PatchSettingsViewModel.errorMessage",
            message: "Authentication failure",
            role: "errorMessage",
            taxonomy: "N10",
            expected: .other("Authentication failure")
        ),
        // MedtrumKitUI/AuthorizeBiometrics.swift:11-13
        Row(
            identifier: "AuthorizeBiometrics.evaluatePolicyReason",
            message: "We need to unlock your data.",
            role: "notificationBody",
            taxonomy: "N10",
            expected: .other("We need to unlock your data.")
        ),
        // MedtrumKit/PumpManager/MedtrumPumpManager.swift:585
        Row(
            identifier: "NSError.syncBasalRateSchedule",
            message: "Basal schedule is empty...",
            role: "validation",
            taxonomy: "N13",
            expected: .other("Basal schedule is empty...")
        ),
        // MedtrumKitUI/ViewModels/Onboarding/PumpBaseSettingsViewModel.swift:32
        Row(
            identifier: "PumpBaseSettingsViewModel.errorMessage",
            message: "Serial Number is too short",
            role: "validation",
            taxonomy: "N13",
            expected: .other("Serial Number is too short")
        ),
        // MedtrumKitUI/ViewModels/Onboarding/PumpBaseSettingsViewModel.swift:38
        Row(
            identifier: "PumpBaseSettingsViewModel.errorMessage",
            message: "Serial Number is invalid hex format",
            role: "validation",
            taxonomy: "N13",
            expected: .other("Serial Number is invalid hex format")
        ),
        // MedtrumKitUI/ViewModels/Onboarding/PumpBaseSettingsViewModel.swift:55
        Row(
            identifier: "PumpBaseSettingsViewModel.errorMessage",
            message: "Incorrect serial number received",
            role: "validation",
            taxonomy: "N13",
            expected: .other("Incorrect serial number received")
        ),
        // MedtrumKit/Packets/Enums/PatchState.swift:73
        Row(
            identifier: "PatchState.noCalibration",
            message: "No Calibration",
            role: "errorMessage",
            taxonomy: "N11",
            expected: .other("No Calibration")
        ),
        // MedtrumKit/Packets/Enums/PatchState.swift:31
        Row(
            identifier: "PatchState.none",
            message: "None",
            role: "errorMessage",
            taxonomy: "N14",
            expected: .other("None")
        ),
        // MedtrumKit/Packets/Enums/PatchState.swift:33
        Row(
            identifier: "PatchState.idle",
            message: "Idle",
            role: "errorMessage",
            taxonomy: "N14",
            expected: .other("Idle")
        ),
        // MedtrumKit/Packets/Enums/PatchState.swift:35
        Row(
            identifier: "PatchState.filled",
            message: "Filled",
            role: "errorMessage",
            taxonomy: "N14",
            expected: .other("Filled")
        ),
        // MedtrumKit/Packets/Enums/PatchState.swift:37
        Row(
            identifier: "PatchState.priming",
            message: "Priming",
            role: "errorMessage",
            taxonomy: "N14",
            expected: .other("Priming")
        ),
        // MedtrumKit/Packets/Enums/PatchState.swift:39
        Row(
            identifier: "PatchState.primed",
            message: "Primed",
            role: "errorMessage",
            taxonomy: "N14",
            expected: .other("Primed")
        ),
        // MedtrumKit/Packets/Enums/PatchState.swift:41
        Row(
            identifier: "PatchState.ejecting",
            message: "Ejecting",
            role: "errorMessage",
            taxonomy: "N14",
            expected: .other("Ejecting")
        ),
        // MedtrumKit/Packets/Enums/PatchState.swift:43
        Row(
            identifier: "PatchState.ejected",
            message: "Ejected",
            role: "errorMessage",
            taxonomy: "N14",
            expected: .other("Ejected")
        ),
        // MedtrumKit/Packets/Enums/PatchState.swift:46
        Row(
            identifier: "PatchState.active",
            message: "Active",
            role: "errorMessage",
            taxonomy: "N14",
            expected: .other("Active")
        ),
        // MedtrumKit/Packets/Enums/PatchState.swift:49
        Row(
            identifier: "PatchState.lowBgSuspended",
            message: "Suspended - Low BG",
            role: "errorMessage",
            taxonomy: "N2",
            expected: .other("Suspended - Low BG")
        ),
        // MedtrumKit/Packets/Enums/PatchState.swift:51
        Row(
            identifier: "PatchState.autoSuspended",
            message: "Suspended - Auto",
            role: "errorMessage",
            taxonomy: "N2",
            expected: .other("Suspended - Auto")
        ),
        // MedtrumKit/Packets/Enums/PatchState.swift:53
        Row(
            identifier: "PatchState.hourlyMaxSuspended",
            message: "Suspended - Hourly Max",
            role: "errorMessage",
            taxonomy: "N2",
            expected: .other("Suspended - Hourly Max")
        ),
        // MedtrumKit/Packets/Enums/PatchState.swift:55
        Row(
            identifier: "PatchState.dailyMaxSuspended",
            message: "Suspended - Daily Max",
            role: "errorMessage",
            taxonomy: "N2",
            expected: .other("Suspended - Daily Max")
        ),
        // MedtrumKit/Packets/Enums/PatchState.swift:57
        Row(
            identifier: "PatchState.suspended",
            message: "Suspended",
            role: "errorMessage",
            taxonomy: "N2",
            expected: .other("Suspended")
        ),
        // MedtrumKit/Packets/Enums/PatchState.swift:59
        Row(
            identifier: "PatchState.paused",
            message: "Paused",
            role: "errorMessage",
            taxonomy: "N2",
            expected: .other("Paused")
        ),
        // MedtrumKit/Packets/Enums/PatchState.swift:61
        // Contains "Occlusion" -> .occlusion.
        Row(
            identifier: "PatchState.occlusion",
            message: "Occlusion",
            role: "errorMessage",
            taxonomy: "N1",
            expected: .occlusion
        ),
        // MedtrumKit/Packets/Enums/PatchState.swift:63
        Row(
            identifier: "PatchState.expired",
            message: "Expired",
            role: "errorMessage",
            taxonomy: "N6",
            expected: .other("Expired")
        ),
        // MedtrumKit/Packets/Enums/PatchState.swift:65
        Row(
            identifier: "PatchState.reservoirEmpty",
            message: "Reservoir Empty",
            role: "errorMessage",
            taxonomy: "N4",
            expected: .other("Reservoir Empty")
        ),
        // MedtrumKit/Packets/Enums/PatchState.swift:69
        // Contains "Fault" -> .hardwareFault.
        Row(
            identifier: "PatchState.baseFault",
            message: "Fault",
            role: "errorMessage",
            taxonomy: "N1",
            expected: .hardwareFault
        ),
        // MedtrumKit/Packets/Enums/PatchState.swift:71
        Row(
            identifier: "PatchState.batteryOut",
            message: "Battery Empty",
            role: "errorMessage",
            taxonomy: "N5",
            expected: .other("Battery Empty")
        ),
        // MedtrumKit/Packets/Enums/PatchState.swift:75
        Row(
            identifier: "PatchState.stopped",
            message: "Stopped",
            role: "errorMessage",
            taxonomy: "N14",
            expected: .other("Stopped")
        ),
        // MedtrumKitUI/Views/Settings/MedtrumKitSettings.swift:85-91
        Row(
            identifier: "MedtrumKitSettings.gracePeriodBanner",
            message: "Change your Patch now. Insulin delivery will stop in %@ or when no more insulin remains.",
            role: "alertBody",
            taxonomy: "F3",
            expected: .other("Change your Patch now. Insulin delivery will stop in %@ or when no more insulin remains.")
        ),
        // MedtrumKitUI/Views/Settings/MedtrumKitSettings.swift:96-107
        Row(
            identifier: "MedtrumKitSettings.hourlyMaxBanner",
            message: "Alert: Hourly max insulin / Patch is suspended. Limit of %lld U exceeded. If you increase the limit, you can clear the alert now. If you wait, patch will resume when enough time passes. / Clear alert",
            role: "alertBody",
            taxonomy: "N2",
            expected: .other(
                "Alert: Hourly max insulin / Patch is suspended. Limit of %lld U exceeded. If you increase the limit, you can clear the alert now. If you wait, patch will resume when enough time passes. / Clear alert"
            )
        ),
        // MedtrumKitUI/Views/Settings/MedtrumKitSettings.swift:126-137
        Row(
            identifier: "MedtrumKitSettings.dailyMaxBanner",
            message: "Alert: Daily max insulin / Patch is suspended. Limit of %lld U exceeded. If you increase the limit, you can clear the alert now. If you wait, patch will resume when enough time passes. / Clear alert",
            role: "alertBody",
            taxonomy: "N2",
            expected: .other(
                "Alert: Daily max insulin / Patch is suspended. Limit of %lld U exceeded. If you increase the limit, you can clear the alert now. If you wait, patch will resume when enough time passes. / Clear alert"
            )
        ),
        // MedtrumKitUI/Views/Onboarding/PatchDeactivationView.swift:43-48
        Row(
            identifier: "PatchDeactivationView.confirmAlert",
            message: "Are you sure? / It is recommended to deactivate first / Confirm",
            role: "alertBody",
            taxonomy: "N14",
            expected: .other("Are you sure? / It is recommended to deactivate first / Confirm")
        ),
        // MedtrumKitUI/Views/DeleteDriverActionSheet.swift:3-19
        Row(
            identifier: "DeleteDriverActionSheet",
            message: "Remove Pump / Are you sure you want to stop using Medtrum TouchCare Nano 200u/300u? / Delete Pump",
            role: "alertBody",
            taxonomy: "N14",
            expected: .other("Remove Pump / Are you sure you want to stop using Medtrum TouchCare Nano 200u/300u? / Delete Pump")
        ),
        // MedtrumKitUI/Views/Settings/MedtrumKitSettings.swift:14-28
        Row(
            identifier: "MedtrumKitSettings.timeSyncActionSheet",
            message: "Time Change Detected / The time on your pump is different from the current time. Do you want to update the time on your pump to the current time? / Yes, Sync to Current Time / No, Keep Pump As Is",
            role: "alertBody",
            taxonomy: "N14",
            expected: .other(
                "Time Change Detected / The time on your pump is different from the current time. Do you want to update the time on your pump to the current time? / Yes, Sync to Current Time / No, Keep Pump As Is"
            )
        ),
        // MedtrumKitUI/Views/Settings/MedtrumKitSettings.swift:30-45
        Row(
            identifier: "MedtrumKitSettings.suspendPickerActionSheet",
            message: "Suspend Insulin Delivery / How long you wish to suspend your patch maximum? It will resume automaticly after this time.",
            role: "alertBody",
            taxonomy: "N14",
            expected: .other(
                "Suspend Insulin Delivery / How long you wish to suspend your patch maximum? It will resume automaticly after this time."
            )
        ),
        // MedtrumKitUI/Views/Settings/MedtrumKitSettings.swift:74-81
        Row(
            identifier: "MedtrumKitSettings.timeSyncBanner",
            message: "Time Change Detected / The time on your pump is different from the current time. Your pump's time controls your scheduled therapy settings. Scroll down to Pump Time row...",
            role: "alertBody",
            taxonomy: "N14",
            expected: .other(
                "Time Change Detected / The time on your pump is different from the current time. Your pump's time controls your scheduled therapy settings. Scroll down to Pump Time row..."
            )
        )
    ]

    @Test("each (identifier, message) classifies as pinned", arguments: rows) func eachMessageClassifiesAsPinned(_ row: Row) {
        #expect(TrioAlertClassifier.categorize(error: StubError(description: row.message)) == row.expected)
    }

    // MARK: - Classifier coverage gaps (ratchet)

    /// `"identifier — message"` keys where the audit marks `isGap == true`:
    /// the message currently falls through to `.other` but SHOULD route to a
    /// meaningful bucket. This ratchet stays green today and FAILS when the
    /// classifier is improved to catch the real prose — prompting an update.
    ///
    /// Per gap: bucket it SHOULD hit, and why the substring tokens miss it.
    ///  - occlusionNotification: SHOULD .occlusion. Body is misspelled
    ///    "occlussion" (double-s) — does NOT contain "occlusion"
    ///    (NotificationManager.swift:61).
    ///  - reservoirEmptyNotification ("...out of insulin!"): SHOULD
    ///    .reservoirEmpty. Prose has no "reservoirempty"/"emptyreservoir"
    ///    token (NotificationManager.swift:81).
    ///  - reservoirEmptyNotification ("Reservoir low..."): SHOULD
    ///    .reservoirLow. "Reservoir low" (with space) != "lowreservoir"
    ///    (NotificationManager.swift:91).
    ///  - PumpStatusHighlight "No Insulin": SHOULD .reservoirEmpty. No
    ///    "reservoirempty" token (MedtrumKitPumpManager+UI.swift:85).
    ///  - PumpStatusHighlight "Patch expired. Basal only.": SHOULD
    ///    .deviceExpired. Only "podexpired"/"sensorexpired" tokens match,
    ///    not "patch expired" (MedtrumKitPumpManager+UI.swift:100).
    ///  - PumpStatusHighlight "Signal Loss": SHOULD .commsTransient. No
    ///    "communication"/"timeout"/etc. token (MedtrumKitPumpManager+UI.swift:109).
    ///  - PumpStatusHighlight "Patch Error": SHOULD .hardwareFault. "Error"
    ///    is not "fault" (MedtrumKitPumpManager+UI.swift:118).
    ///  - failedToDiscoverServices: SHOULD .commsTransient. No comms token
    ///    in the prose (PeripheralManager.swift:209).
    ///  - failedToDiscoverCharacteristics: SHOULD .commsTransient. No comms
    ///    token (PeripheralManager.swift:231).
    ///  - failedToFindDevice "Failed to connect to patch": SHOULD
    ///    .commsTransient. No "timeout"/"notconnected" token; "connect" is
    ///    not "notconnected" (BluetoothManager.swift:114,128).
    ///  - invalidBluetoothState: SHOULD .commsTransient. No comms token
    ///    (BluetoothManager.swift:45).
    ///  - noData "No data": SHOULD .commsTransient. No comms token
    ///    (PeripheralManager.swift:39,71).
    ///  - noWriteCharacteristic: SHOULD .commsTransient. "disconnected" !=
    ///    "notconnected" (PeripheralManager.swift:58).
    ///  - invalidData "Invalid data received": SHOULD .commsTransient. No
    ///    comms token (PeripheralManager.swift:314,321).
    ///  - noManager "No peripheral manager": SHOULD .commsTransient. No
    ///    comms token (BluetoothManager.swift:170).
    ///  - uncertainDelivery "uncertain delivery": SHOULD .deliveryUncertain.
    ///    "uncertain delivery" (with space) != "uncertaindelivery"
    ///    (MedtrumPumpManager.swift:992).
    static let classifierCoverageGaps: Set<String> = [
        "NotificationManager.Identifiers.occlusionNotification — Replace your patch now! / Your patch has detected an occlussion!",
        "NotificationManager.Identifiers.reservoirEmptyNotification — Replace your patch now! / Your patch is out of insulin!",
        "NotificationManager.Identifiers.reservoirEmptyNotification — Reservoir low (%lld U) / Your patch is running out of insulin!",
        "PumpStatusHighlight — No Insulin",
        "PumpStatusHighlight — Patch expired. Basal only.",
        "PumpStatusHighlight — Signal Loss",
        "PumpStatusHighlight — Patch Error",
        "MedtrumConnectError.failedToDiscoverServices — No Medtrum service found - <discovered service UUIDs>",
        "MedtrumConnectError.failedToDiscoverCharacteristics — Failed to discover read, write or config characteristic - <UUIDs>",
        "MedtrumConnectError.failedToFindDevice — Failed to connect to patch",
        "MedtrumScanError.invalidBluetoothState — Invalid Bluetooth state: <state>",
        "MedtrumWriteError.noData — No data",
        "MedtrumWriteError.noWriteCharacteristic — No write characteristic. Device might be disconnected",
        "MedtrumWriteError.invalidData — Invalid data received",
        "MedtrumWriteError.noManager — No peripheral manager",
        "PumpManagerError.uncertainDelivery — uncertain delivery"
    ]

    @Test("classifier coverage gaps are exactly as documented") func classifierCoverageGapsAreExactlyAsDocumented() {
        // A coverage gap = a row that currently resolves to `.other(message)`
        // even though the audit says it SHOULD route to a meaningful bucket
        // (taxonomyBucket != "other"). The bucket-vs-other distinction lives
        // in the audit, encoded here as `classifierCoverageGaps`. Recompute
        // the falls-through-to-other set among gap-flagged rows and confirm
        // it matches verbatim; this FAILS when the classifier is improved to
        // catch the prose, forcing the documented set to be updated.
        let fellThroughToOther = Set(
            Self.rows
                .filter { row in
                    TrioAlertClassifier.categorize(error: StubError(description: row.message)) == .other(row.message)
                }
                .map { "\($0.identifier) — \($0.message)" }
        )
        let documentedGapsThatFellThrough = fellThroughToOther.intersection(Self.classifierCoverageGaps)
        #expect(documentedGapsThatFellThrough == Self.classifierCoverageGaps)
    }
}
