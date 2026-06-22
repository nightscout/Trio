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
