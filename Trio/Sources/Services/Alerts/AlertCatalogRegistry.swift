import LoopKit

/// Trio-side bridge of the upstream `AlertCatalogVendor` protocol. Pump
/// plugins don't currently set `interruptionLevel` on the alerts they issue
/// — every emission lands at LoopKit's default (`.timeSensitive`). Trio
/// overrides the level by looking up the alert's identifier in this
/// registry. As plugins adopt `AlertCatalogVendor` upstream, their entries
/// move out of here and into the plugin repo.
///
/// Scope covers pump + CGM-issued alerts (LibreLoop sensor expiry / attention
/// / reconnect). G5/G6/One/G7/One+ don't go through `issueAlert` — their
/// status surfaces via `cgmStatusHighlight` instead. Trio-internal alerts
/// (glucose thresholds, algorithm error, not-looping) set their level at
/// construction and don't need a catalog entry.
enum AlertCatalogRegistry {
    static let entries: [Alert.CatalogEntry] =
        omniEntries + minimedEntries + danaEntries + medtrumEntries + tandemEntries + libreLoopEntries +
        trioAlgorithmEntries

    static func lookup(_ identifier: Alert.Identifier) -> Alert.CatalogEntry? {
        if let exact = entries.first(where: { $0.identifier == identifier }) {
            return exact
        }
        if let tandem = tandemEntry(for: identifier) {
            return tandem
        }
        if let warning = notLoopingWarningEntry(for: identifier) {
            return warning
        }
        return omniPodFaultEntry(for: identifier)
    }

    /// `NotLoopingMonitor` arms one warning per escalation step
    /// (`loop.notActive.w1` … `w5`), each needing its own pending notification,
    /// so they can't share a single identifier. They all resolve to the same
    /// Time-Sensitive entry rather than being listed individually — the
    /// Critical escalation keeps the bare `loop.notActive` identifier.
    private static func notLoopingWarningEntry(for identifier: Alert.Identifier) -> Alert.CatalogEntry? {
        guard identifier.managerIdentifier == "trio.aps",
              identifier.alertIdentifier.hasPrefix("loop.notActive.")
        else { return nil }
        return Alert.CatalogEntry(
            identifier: identifier, interruptionLevel: .timeSensitive,
            title: "Trio Not Looping", category: "Algorithm", concept: .notLooping
        )
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
        // MedtrumKit currently emits the occlusion alert with a misspelled
        // identifier ("patch-occlussion", double "s") — see MedtrumKit's
        // NotificationManager. We register both the misspelled identifier (what
        // ships today) and the corrected spelling so the alert escalates to
        // critical regardless of which MedtrumKit is bundled. Drop the
        // misspelled entry once the typo is fixed upstream.
        addEntry("Medtrum", "com.nightscout.medtrumkit.patch-occlussion", .critical, "Occlusion", "Delivery", .occlusion),
        addEntry("Medtrum", "com.nightscout.medtrumkit.patch-occlusion", .critical, "Occlusion", "Delivery", .occlusion),
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

// MARK: - Tandem (Mobi)

private extension AlertCatalogRegistry {
    /// TandemKit mints one identifier per notification bit — `<category>.<slug>.<bit>`, or
    /// `malfunction.<aamId>` where there is no condition enum to slug (TandemKit's
    /// `NotificationBundle.stableIdentifier`). The bit position varies by firmware, so these
    /// entries are keyed on the `<category>.<slug>` prefix that TandemKit documents as stable
    /// alert identity; `tandemEntry(for:)` strips the trailing bit before matching.
    ///
    /// Levels track the severity TandemKit issues with (`PumpNotificationSeverity`): alarms and
    /// malfunctions accompany stopped or compromised delivery, alerts are actionable but not
    /// immediately dangerous.
    ///
    /// Tandem's CGM alerts are deliberately absent. They only arrive when the user opts into
    /// forwarding (`forwardCGMAlerts`), they duplicate Trio's own glucose alarms, and the
    /// glucose-threshold ones have no device concept to collapse onto — so they pass through at
    /// the level TandemKit set, uncatalogued, until there is a concept that fits them.
    static let tandemEntries: [Alert.CatalogEntry] = [
        // Alarms: delivery is stopped or compromised.
        addEntry("Tandem", "alarm.occlusion", .critical, "Occlusion", "Delivery", .occlusion),
        addEntry("Tandem", "alarm.emptyCartridge", .critical, "Cartridge Empty", "Reservoir", .reservoirEmpty),
        addEntry("Tandem", "alarm.cartridge", .critical, "Cartridge Error", "Reservoir", .hardwareFault),
        addEntry("Tandem", "alarm.cartridgeRemoved", .critical, "Cartridge Removed", "Reservoir", .hardwareFault),
        addEntry("Tandem", "alarm.resumePump", .critical, "Resume Pump", "Delivery", .insulinResumeReminder),
        addEntry("Tandem", "alarm.autoOff", .critical, "Auto-Off", "Delivery", .insulinResumeReminder),
        addEntry("Tandem", "alarm.pumpReset", .critical, "Pump Reset", "Hardware", .hardwareFault),
        addEntry("Tandem", "alarm.batteryShutdown", .critical, "Battery Shutdown", "Battery", .pumpBatteryEmpty),
        addEntry("Tandem", "alarm.temperature", .critical, "Temperature Out of Range", "Hardware", .hardwareFault),
        addEntry("Tandem", "alarm.altitude", .critical, "Altitude Out of Range", "Hardware", .hardwareFault),
        addEntry("Tandem", "alarm.atmosphericPressure", .critical, "Pressure Out of Range", "Hardware", .hardwareFault),
        addEntry("Tandem", "alarm.invalidDate", .critical, "Invalid Date", "Hardware", .hardwareFault),
        addEntry("Tandem", "alarm.stuckButton", .critical, "Stuck Button", "Hardware", .hardwareFault),
        // Category fallbacks: an unmapped bit still escalates with its category.
        addEntry("Tandem", "alarm.other", .critical, "Pump Alarm", "Hardware", .hardwareFault),
        addEntry("Tandem", "malfunction", .critical, "Pump Malfunction", "Hardware", .hardwareFault),

        // Alerts: actionable, not immediately dangerous.
        addEntry("Tandem", "alert.lowInsulin", .timeSensitive, "Low Insulin", "Reservoir", .reservoirLow),
        addEntry("Tandem", "alert.lowPower", .timeSensitive, "Low Pump Battery", "Battery", .pumpBatteryLow),
        addEntry("Tandem", "alert.powerSource", .timeSensitive, "Charging Problem", "Battery", .pumpBatteryLow),
        addEntry("Tandem", "alert.usbConnection", .active, "USB Connection", "Battery", .pumpBatteryLow),
        addEntry("Tandem", "alert.autoOff", .timeSensitive, "Auto-Off Warning", "Delivery", .deviceShutdownImminent),
        addEntry("Tandem", "alert.maxBasal", .timeSensitive, "Basal Limit Reached", "Delivery", .insulinLimitReached),
        addEntry("Tandem", "alert.maxBasalRate", .timeSensitive, "Basal Limit Warning", "Delivery", .insulinLimitWarning),
        addEntry("Tandem", "alert.minBasal", .timeSensitive, "Minimum Basal", "Delivery", .insulinLimitWarning),
        addEntry("Tandem", "alert.incompleteBolus", .timeSensitive, "Incomplete Bolus", "Delivery", .setupIncomplete),
        addEntry(
            "Tandem",
            "alert.incompleteTempRate",
            .timeSensitive,
            "Incomplete Temp Rate",
            "Delivery",
            .setupIncomplete
        ),
        addEntry(
            "Tandem",
            "alert.incompleteCartridgeChange",
            .timeSensitive,
            "Incomplete Cartridge Change",
            "Reservoir",
            .setupIncomplete
        ),
        addEntry("Tandem", "alert.incompleteFillTubing", .timeSensitive, "Incomplete Fill Tubing", "Setup", .setupIncomplete),
        addEntry(
            "Tandem",
            "alert.incompleteFillCannula",
            .timeSensitive,
            "Incomplete Fill Cannula",
            "Setup",
            .setupIncomplete
        ),
        addEntry("Tandem", "alert.incompleteSetting", .timeSensitive, "Incomplete Setting", "Setup", .setupIncomplete),
        addEntry("Tandem", "alert.fillTubingInProgress", .active, "Fill Tubing In Progress", "Setup", .setupIncomplete),
        addEntry("Tandem", "alert.connectionError", .timeSensitive, "Pump Connection Error", "Connectivity", .pairingFailed),
        addEntry(
            "Tandem",
            "alert.deviceConnectionError",
            .timeSensitive,
            "Device Connection Error",
            "Connectivity",
            .pairingFailed
        ),
        addEntry("Tandem", "alert.devicePaired", .active, "Device Paired", "Connectivity", .pairingFailed),
        addEntry("Tandem", "alert.pumpRebooting", .timeSensitive, "Pump Rebooting", "Hardware", .hardwareFault),
        addEntry("Tandem", "alert.dataError", .timeSensitive, "Data Error", "Hardware", .hardwareFault),
        addEntry("Tandem", "alert.button", .active, "Button Alert", "Hardware", .hardwareFault),
        addEntry("Tandem", "alert.other", .timeSensitive, "Pump Alert", "Hardware", .hardwareFault)
    ]

    /// Resolves a Tandem identifier by its `<category>.<slug>` prefix, falling back to
    /// `<category>.other` so a firmware that adds a notification bit still lands in the right
    /// tier instead of bypassing the Device Alarms configuration entirely. Returns the match
    /// re-stamped with the incoming identifier, so callers that key off `entry.identifier`
    /// (snooze, tier dismissal) see the alert they were handed.
    static func tandemEntry(for identifier: Alert.Identifier) -> Alert.CatalogEntry? {
        guard identifier.managerIdentifier == "Tandem" else { return nil }
        let segments = identifier.alertIdentifier.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count >= 2, let last = segments.last, UInt32(last) != nil else { return nil }

        let prefix = segments.dropLast().joined(separator: ".")
        guard let category = segments.first, !category.isEmpty else { return nil }
        let template = tandemEntries.first { $0.identifier.alertIdentifier == prefix }
            ?? tandemEntries.first { $0.identifier.alertIdentifier == "\(category).other" }
        guard let template else { return nil }

        return Alert.CatalogEntry(
            identifier: identifier,
            interruptionLevel: template.interruptionLevel,
            title: template.title,
            category: template.category,
            concept: template.concept
        )
    }
}

// MARK: - LibreLoop (FreeStyle Libre 3)

private extension AlertCatalogRegistry {
    /// Manager identifier matches `LibreLoopCGMManager.pluginIdentifier`.
    /// Alert identifiers come from `LibreLoopExpiryAlerts` +
    /// `LibreLoopCGMManager.sensorAttentionAlertID` /
    /// `needsReScanAlertID`.
    ///
    /// Levels track what LibreLoop itself issues: nothing here is `.critical`,
    /// because none of these are act-immediately-or-be-harmed events — a sensor
    /// ending or needing a re-scan pauses CGM, it doesn't dose insulin. Keeping
    /// them `.timeSensitive` also leaves them snoozeable (`.critical` bypasses
    /// snooze) and keeps genuine critical alarms meaningful.
    ///
    /// `sensorAttention` is one identifier covering three upstream states
    /// (replace / ended / transient check), so a single level here is a
    /// compromise — `.timeSensitive` fits replace + ended, and over-states the
    /// transient case by one notch. Splitting it upstream is the real fix.
    static let libreLoopEntries: [Alert.CatalogEntry] = [
        addEntry(
            "LibreLoopCGMManager",
            "sensorExpiry.warning24h",
            .timeSensitive,
            "Sensor Expires in 24 Hours",
            "Sensor",
            .cgmExpiringSoon
        ),
        addEntry(
            "LibreLoopCGMManager",
            "sensorExpiry.warning2h",
            .timeSensitive,
            "Sensor Expires in 2 Hours",
            "Sensor",
            .cgmExpiringSoon
        ),
        addEntry(
            "LibreLoopCGMManager",
            "sensorExpiry.sessionEnded",
            .timeSensitive,
            "Sensor Session Ended",
            "Sensor",
            .cgmExpired
        ),
        addEntry(
            "LibreLoopCGMManager",
            "sensorAttention",
            .timeSensitive,
            "Sensor Attention",
            "Sensor",
            .cgmReplacementNeeded
        ),
        addEntry(
            "LibreLoopCGMManager",
            "reconnectNeedsReScan",
            .timeSensitive,
            "Re-scan Sensor",
            "Connectivity",
            .cgmReconnectNeeded
        )
    ]
}

// MARK: - Trio internal — Algorithm

private extension AlertCatalogRegistry {
    /// Trio-internal alerts emitted under `manager = "trio.aps"`. Levels
    /// match what `APSManager.issueAlertFor…` / `NotLoopingMonitor` set at
    /// construction; the catalog presence is what lets these surface in the
    /// Device Alarms screen alongside pump and CGM entries.
    /// `loop.notActive` matches `NotLoopingMonitor.alertID`; other slugs
    /// come from `TrioAlertCategory.alertIdentifier`.
    static let trioAlgorithmEntries: [Alert.CatalogEntry] = [
        addEntry("trio.aps", "loop.notActive", .critical, "Trio Not Looping", "Algorithm", .notLooping),
        addEntry("trio.aps", "algorithmError", .active, "Algorithm Error", "Algorithm", .algorithmError),
        addEntry("trio.aps", "glucoseDataStale", .timeSensitive, "Glucose Data Stale", "Algorithm", .glucoseDataStale)
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
