import Foundation

/// One source for the text of a running adjustment, so every place that shows it shows the same text.
struct AdjustmentDescriber {
    let units: GlucoseUnits
    let maxSMBBasalMinutes: Decimal
    let maxUAMSMBBasalMinutes: Decimal
    let settingHalfBasalTarget: Decimal
    let autosensMax: Decimal
    let isExerciseModeActive: Bool
    let highTTraisesSens: Bool
    let lowTTlowersSens: Bool

    static func remainingMinutes(start: Date?, durationMinutes: NSDecimalNumber?, now: Date = Date()) -> Decimal {
        let addedMinutes = Int(truncating: durationMinutes ?? 0)
        let end = (start ?? now).addingTimeInterval(TimeInterval(addedMinutes * 60))
        return max(Decimal(now.distance(to: end).minutes), 0)
    }

    static func isExpired(_ override: OverrideStored, now: Date = Date()) -> Bool {
        !override.indefinite && remainingMinutes(start: override.date, durationMinutes: override.duration, now: now) <= 0
    }

    static func isExpired(_ tempTarget: TempTargetStored, now: Date = Date()) -> Bool {
        remainingMinutes(start: tempTarget.date, durationMinutes: tempTarget.duration, now: now) <= 0
    }

    static func name(of override: OverrideStored?) -> String {
        override?.name ?? String(localized: "Custom Override")
    }

    static func name(of tempTarget: TempTargetStored?) -> String {
        tempTarget?.name ?? String(localized: "Temp Target")
    }

    /// Returns nil when nothing in the override differs from the profile.
    /// - Parameter showsTarget: false while a temp target runs, because the temp target then sets the target.
    func overrideDetails(_ override: OverrideStored, showsTarget: Bool, now: Date = Date()) -> String? {
        let percent = override.percentage
        let percentString = percent == 100 ? "" : "\(percent.formatted(.number)) %"

        let target = (override.target ?? 0) as Decimal
        let targetString = target == 0 || !showsTarget ? "" : target.formatted(withUnits: units)

        let remaining = Self.remainingMinutes(start: override.date, durationMinutes: override.duration, now: now)
        var durationString = ""
        if !override.indefinite {
            if remaining >= 1 {
                durationString = formatHrMin(Int(remaining))
            } else if remaining > 0 {
                durationString = "\(Int(remaining * 60)) s"
            }
        }

        let smbScheduleString = override
            .smbIsScheduledOff && ((override.start?.stringValue ?? "") != (override.end?.stringValue ?? ""))
            ? " \(formatTimeRange(start: override.start?.stringValue, end: override.end?.stringValue))"
            : ""

        let smbToggleString = override.smbIsOff || override
            .smbIsScheduledOff ? String(localized: "SMBs Off\(smbScheduleString)") : ""

        var smbMinuteString: String = ""
        var uamMinuteString: String = ""

        if !override.smbIsOff, override.advancedSettings {
            if let smbMinutes = override.smbMinutes, smbMinutes.decimalValue != maxSMBBasalMinutes {
                smbMinuteString = "SMB\u{00A0}\(smbMinutes)\u{00A0}" +
                    String(localized: "m", comment: "Abbreviation for Minutes")
            }

            if let uamMinutes = override.uamMinutes, uamMinutes.decimalValue != maxUAMSMBBasalMinutes {
                uamMinuteString = "UAM\u{00A0}\(uamMinutes)\u{00A0}" +
                    String(localized: "m", comment: "Abbreviation for Minutes")
            }
        }

        let components = [durationString, percentString, targetString, smbToggleString, smbMinuteString, uamMinuteString]
            .filter { !$0.isEmpty }
        return components.isEmpty ? nil : components.joined(separator: ", ")
    }

    /// Returns nil when the temp target has neither a target nor time left.
    func tempTargetDetails(_ tempTarget: TempTargetStored, now: Date = Date()) -> String? {
        let remaining = Self.remainingMinutes(start: tempTarget.date, durationMinutes: tempTarget.duration, now: now)
        var durationString = ""
        var percentageString = ""
        let target = (tempTarget.target ?? 100) as Decimal
        let effectiveHBT = TempTargetCalculations.computeEffectiveHBT(
            tempTargetHalfBasalTarget: tempTarget.halfBasalTarget?.decimalValue,
            settingHalfBasalTarget: settingHalfBasalTarget,
            target: target,
            autosensMax: autosensMax
        ) ?? settingHalfBasalTarget
        var showPercentage = false
        if target > 100, isExerciseModeActive || highTTraisesSens { showPercentage = true }
        if target < 100, lowTTlowersSens, autosensMax > 1 { showPercentage = true }
        if showPercentage {
            percentageString =
                " \(Int(TempTargetCalculations.computeAdjustedPercentage(halfBasalTarget: effectiveHBT, target: target, autosensMax: autosensMax)))%"
        }
        let targetString = target == 0 ? "" : target.formatted(withUnits: units) + percentageString

        if remaining >= 1 {
            durationString =
                "\(remaining.formatted(.number.grouping(.never).rounded().precision(.fractionLength(0)))) min"
        } else if remaining > 0 {
            durationString =
                "\((remaining * 60).formatted(.number.grouping(.never).rounded().precision(.fractionLength(0)))) s"
        }

        let components = [targetString, durationString].filter { !$0.isEmpty }
        return components.isEmpty ? nil : components.joined(separator: ", ")
    }
}

extension AdjustmentDescriber {
    init(units: GlucoseUnits, preferences: Preferences) {
        self.init(
            units: units,
            maxSMBBasalMinutes: preferences.maxSMBBasalMinutes,
            maxUAMSMBBasalMinutes: preferences.maxUAMSMBBasalMinutes,
            settingHalfBasalTarget: preferences.halfBasalExerciseTarget,
            autosensMax: preferences.autosensMax,
            isExerciseModeActive: preferences.exerciseMode,
            highTTraisesSens: preferences.highTemptargetRaisesSensitivity,
            lowTTlowersSens: preferences.lowTemptargetLowersSensitivity
        )
    }
}
