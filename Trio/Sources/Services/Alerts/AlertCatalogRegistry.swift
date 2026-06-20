import LoopKit

/// Trio-side bridge of the upstream `AlertCatalogVendor` protocol. Pump
/// plugins don't currently set `interruptionLevel` on the alerts they issue
/// — every emission lands at LoopKit's default (`.timeSensitive`). Trio
/// overrides the level by looking up the alert's identifier in this
/// registry. As plugins adopt `AlertCatalogVendor` upstream, their entries
/// move out of here and into the plugin repo.
///
/// Scope is pump alerts only. CGM lifecycle alerts (LibreLoop sensor end,
/// etc.) pass through with the plugin's chosen level. Trio-internal alerts
/// (glucose thresholds, algorithm error, not-looping) set their level at
/// construction and don't need a catalog entry.
enum AlertCatalogRegistry {
    static let entries: [Alert.CatalogEntry] = omniEntries + minimedEntries + danaEntries + medtrumEntries

    static func lookup(_ identifier: Alert.Identifier) -> Alert.CatalogEntry? {
        if let exact = entries.first(where: { $0.identifier == identifier }) {
            return exact
        }
        return omniPodFaultEntry(for: identifier)
    }

    /// Omni emits pod faults via `notifyPodFault` with a separate manager
    /// identifier (`Omni:pumpFault`) and a formatted alert identifier
    /// (`Fault Event Code 0xNN: ...`). Map the small set of user-relevant
    /// codes to concrete concepts; everything else falls back to a generic
    /// `Pod Fault` so it still surfaces under the Critical tier.
    private static func omniPodFaultEntry(for identifier: Alert.Identifier) -> Alert.CatalogEntry? {
        guard identifier.managerIdentifier == "Omni:pumpFault" else { return nil }
        let code = parseOmniFaultHexCode(from: identifier.alertIdentifier)
        switch code {
        case 0x14:
            return Alert.CatalogEntry(
                identifier: identifier, interruptionLevel: .critical,
                title: "Pod Occlusion", category: "Delivery", concept: .occlusion
            )
        case 0x18:
            return Alert.CatalogEntry(
                identifier: identifier, interruptionLevel: .critical,
                title: "Pod Reservoir Empty", category: "Reservoir", concept: .reservoirEmpty
            )
        case 0x1C:
            return Alert.CatalogEntry(
                identifier: identifier, interruptionLevel: .timeSensitive,
                title: "Pod Expired", category: "Lifecycle", concept: .deviceExpired
            )
        default:
            return Alert.CatalogEntry(
                identifier: identifier, interruptionLevel: .critical,
                title: "Pod Fault", category: "Hardware", concept: .hardwareFault
            )
        }
    }

    /// Extracts the hex code from `Fault Event Code 0xNN: ...`. Bounded
    /// parser, not a substring classifier — the prefix shape is fixed by
    /// `FaultEventCode.description`.
    private static func parseOmniFaultHexCode(from alertID: String) -> UInt8? {
        let prefix = "Fault Event Code 0x"
        guard alertID.hasPrefix(prefix), alertID.count >= prefix.count + 2 else { return nil }
        let start = alertID.index(alertID.startIndex, offsetBy: prefix.count)
        let end = alertID.index(start, offsetBy: 2)
        return UInt8(alertID[start ..< end], radix: 16)
    }
}

// MARK: - Omnipod (Eros + DASH)

private extension AlertCatalogRegistry {
    static let omniEntries: [Alert.CatalogEntry] = [
        addEntry("Omni", "userPodExpiration", .active, "Pod Expiration Reminder", "Lifecycle", .deviceExpirationReminder),
        addEntry("Omni", "podExpiring", .timeSensitive, "Pod Expired", "Lifecycle", .deviceExpired),
        addEntry("Omni", "podExpireImminent", .timeSensitive, "Pod Shutdown Imminent", "Lifecycle", .deviceShutdownImminent),
        addEntry("Omni", "lowReservoir", .timeSensitive, "Low Reservoir", "Reservoir", .reservoirLow),
        addEntry("Omni", "suspendInProgress", .active, "Suspend In Progress Reminder", "Delivery", .suspendInProgressReminder),
        addEntry("Omni", "suspendEnded", .timeSensitive, "Resume Insulin", "Delivery", .insulinResumeReminder),
        addEntry("Omni", "finishSetupReminder", .active, "Pod Pairing Incomplete", "Lifecycle", .setupIncomplete),
        addEntry("Omni", "unexpectedAlert", .critical, "Unexpected Alert", "Hardware", .hardwareFault),
        addEntry("Omni", "timeOffsetChangeDetected", .active, "Time Change Detected", "Lifecycle", .timeChange),
        addEntry("Omni", "lowRLBattery", .timeSensitive, "Low RileyLink Battery", "Battery", .rileyLinkBatteryLow)
    ]
}

// MARK: - Minimed (500/700)

private extension AlertCatalogRegistry {
    static let minimedEntries: [Alert.CatalogEntry] = [
        addEntry("Minimed", "PumpBatteryLow", .timeSensitive, "Pump Battery Low", "Battery", .pumpBatteryLow),
        addEntry("Minimed", "PumpReservoirEmpty", .critical, "Pump Reservoir Empty", "Reservoir", .reservoirEmpty),
        addEntry("Minimed", "PumpReservoirLow", .timeSensitive, "Pump Reservoir Low", "Reservoir", .reservoirLow),
        addEntry("Minimed", "lowRLBattery", .timeSensitive, "Low RileyLink Battery", "Battery", .rileyLinkBatteryLow)
    ]
}

// MARK: - Dana (RS/i/-i)

private extension AlertCatalogRegistry {
    static let danaEntries: [Alert.CatalogEntry] = [
        addEntry("Dana", "batteryZeroPercent", .critical, "Pump Battery 0%", "Battery", .pumpBatteryEmpty),
        addEntry("Dana", "pumpError", .critical, "Pump Error", "Hardware", .hardwareFault),
        addEntry("Dana", "occlusion", .critical, "Occlusion", "Delivery", .occlusion),
        addEntry("Dana", "lowBattery", .timeSensitive, "Low Pump Battery", "Battery", .pumpBatteryLow),
        addEntry("Dana", "shutdown", .critical, "Pump Shutdown", "Hardware", .hardwareFault),
        addEntry("Dana", "basalCompare", .active, "Basal Compare", "Delivery", .basalProfileMismatch),
        addEntry("Dana", "bloodSugarMeasure", .active, "Blood Glucose Measure", "Reminders", .userBloodGlucoseReminder),
        addEntry("Dana", "remainingInsulinLevel", .timeSensitive, "Remaining Insulin Level", "Reservoir", .reservoirLow),
        addEntry("Dana", "emptyReservoir", .critical, "Empty Reservoir", "Reservoir", .reservoirEmpty),
        addEntry("Dana", "checkShaft", .critical, "Check Shaft", "Hardware", .hardwareFault),
        addEntry("Dana", "basalMax", .active, "Basal Limit Reached", "Delivery", .insulinLimitWarning),
        addEntry("Dana", "dailyMax", .active, "Daily Limit Reached", "Delivery", .insulinLimitWarning),
        addEntry("Dana", "bloodSugarCheckMiss", .active, "Missed Blood Glucose Check", "Reminders", .userBloodGlucoseReminder),
        addEntry("Dana", "ble5InvalidKeys", .timeSensitive, "Pairing Failed", "Connectivity", .pairingFailed),
        addEntry("Dana", "unknown", .timeSensitive, "Unknown Pump Error", "Hardware", .hardwareFault)
    ]
}

// MARK: - Medtrum (TouchCare nano)

private extension AlertCatalogRegistry {
    static let medtrumEntries: [Alert.CatalogEntry] = [
        addEntry(
            "Medtrum",
            "com.nightscout.medtrumkit.patch-expired",
            .active,
            "Patch Expiring Soon",
            "Lifecycle",
            .deviceExpirationReminder
        ),
        addEntry(
            "Medtrum",
            "com.nightscout.medtrumkit.patch-daily-limit",
            .timeSensitive,
            "Daily Insulin Limit",
            "Delivery",
            .insulinLimitReached
        ),
        addEntry(
            "Medtrum",
            "com.nightscout.medtrumkit.patch-hourly-limit",
            .timeSensitive,
            "Hourly Insulin Limit",
            "Delivery",
            .insulinLimitReached
        ),
        addEntry("Medtrum", "com.nightscout.medtrumkit.patch-occlussion", .critical, "Occlusion", "Delivery", .occlusion),
        addEntry("Medtrum", "com.nightscout.medtrumkit.patch-fault", .critical, "Patch Fault", "Hardware", .hardwareFault),
        addEntry("Medtrum", "com.nightscout.medtrumkit.patch-empty", .critical, "Reservoir Empty", "Reservoir", .reservoirEmpty),
        addEntry(
            "Medtrum",
            "com.nightscout.medtrumkit.reservoir-low",
            .timeSensitive,
            "Reservoir Low",
            "Reservoir",
            .reservoirLow
        )
    ]
}

// MARK: - Helpers

private extension AlertCatalogRegistry {
    static func addEntry(
        _ manager: String,
        _ alertID: String,
        _ level: Alert.InterruptionLevel,
        _ title: String,
        _ category: String,
        _ concept: Alert.CatalogConcept
    ) -> Alert.CatalogEntry {
        Alert.CatalogEntry(
            managerIdentifier: manager,
            alertIdentifier: alertID,
            interruptionLevel: level,
            title: title,
            category: category,
            concept: concept
        )
    }
}
