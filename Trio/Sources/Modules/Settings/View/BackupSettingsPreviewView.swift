import CoreFoundation
import Foundation
import SwiftUI

/// Read-only values from the saved snapshot; never resolves live settings.
struct BackupSettingsNode: Identifiable {
    let id: String
    let title: String
    var value: String? = nil
    var children: [Self] = []
    var note: String? = nil
    var isGroupedRow = false

    static func make(from backup: TrioSettingsBackup) -> [Self] {
        var builder = Builder(configuration: backup.configuration)
        builder.addFields(backup.configuration.settings, source: "trioSettings")
        builder.addFields(backup.configuration.preferences, source: "preferences")
        builder.addFields(backup.configuration.pumpSettings, source: "pumpSettings")
        builder.addSchedules()
        builder.addEncoded(backup.configuration.presets.overrides, title: "Overrides", path: ["Presets"])
        builder.addEncoded(backup.configuration.presets.tempTargets, title: "Temporary Targets", path: ["Presets"])
        builder.addEncoded(
            backup.configuration.presets.meals,
            title: "Meals",
            path: ["Presets"]
        )
        if let app = backup.configuration.appConfiguration {
            builder.add(
                .init(id: "appearance", title: "Appearance", value: Self.format(app.appearance)),
                path: ["Features", "User Interface"]
            )
            if let order = app.liveActivityOrder {
                builder.addEncoded(order, title: "Display Order", path: ["Notifications", "Live Activity"])
            }
            builder.addEncoded(app.glucoseAlerts, title: "Glucose Alarms", path: ["Notifications"])
            builder.addAlertPreferences(app.glucoseAlertConfiguration)
            builder.addEncoded(app.deviceAlertConfigurations, title: "Device Alarms", path: ["Notifications"])
        }
        builder.addDynamicISFSetting()
        builder.addHistory(backup.dynamicISFHistory)
        builder.groupCompoundSettings()
        builder.addAlertWindowLinks()
        return builder.roots.filter { !$0.children.isEmpty || $0.value != nil }
    }

    struct PreviewSection: Identifiable {
        let id: String
        let title: String?
        let rows: [BackupSettingsNode]
    }

    private struct Layout {
        let title: String?
        let rows: [String]
    }

    var navigationTitle: String {
        switch id {
        case "therapy": return "Therapy Settings"
        case "algorithm": return "Algorithm Settings"
        case "features": return "Feature Settings"
        case "Devices/Smart Watch": return "Watch"
        default: return title
        }
    }

    var sections: [PreviewSection] {
        guard let layouts = Self.layouts[id] else {
            return [.init(id: id, title: nil, rows: children)]
        }
        var used: Set<String> = []
        var result: [PreviewSection] = []
        for (index, layout) in layouts.enumerated() {
            let rows = layout.rows.compactMap { title in children.first { $0.title == title } }
            used.formUnion(rows.map(\.id))
            if !rows.isEmpty { result.append(.init(id: "\(id)-\(index)", title: layout.title, rows: rows)) }
        }
        let remaining = children.filter { !used.contains($0.id) }
        if !remaining.isEmpty { result.append(.init(id: id + "-remaining", title: nil, rows: remaining)) }
        return result
    }

    private static let layouts: [String: [Layout]] = [
        "devices": [.init(title: "Setup & Configuration", rows: ["Continuous Glucose Monitor", "Smart Watch"])],
        "Therapy/Units and Limits": [
            .init(title: "Trio Core Setup", rows: ["Glucose Units"]),
            .init(
                title: nil,
                rows: [
                    "Maximum Insulin on Board (IOB)",
                    "Maximum Bolus",
                    "Maximum Basal Rate",
                    "Maximum Carbs on Board (COB)",
                    "Minimum Safety Threshold"
                ]
            )
        ],
        "therapy": [
            .init(title: "Basic Settings", rows: ["Units and Limits"]),
            .init(
                title: "Basic Insulin Rates & Targets",
                rows: ["Glucose Targets", "Basal Rates", "Carb Ratios", "Insulin Sensitivities"]
            )
        ],
        "algorithm": [.init(
            title: "Oref Algorithm",
            rows: ["Autosens", "Super Micro Bolus (SMB)", "Dynamic Settings", "Target Behavior", "Additionals"]
        )],
        "features": [
            .init(title: "Trio Features", rows: ["Treatments", "Shortcuts"]),
            .init(title: "Trio Personalization", rows: ["User Interface"]),
            .init(title: "Anonymized Data Sharing", rows: ["App Diagnostics"])
        ],
        "Algorithm/Dynamic Settings": [
            .init(title: "Dynamic Insulin Sensitivity", rows: ["Dynamic ISF"]),
            .init(
                title: nil,
                rows: ["Adjustment Factor (AF)", "Sigmoid Adjustment Factor", "Weighted Average of TDD", "Adjust Basal"]
            ),
            .init(title: "Dynamic ISF History", rows: ["Dynamic ISF History"])
        ],
        "Features/User Interface": [
            .init(title: "General Appearance", rows: ["Appearance", "Glucose Color Scheme"]),
            .init(
                title: "Home View Settings",
                rows: [
                    "Chart Grid Lines",
                    "Show Low and High Thresholds",
                    "Glucose Thresholds",
                    "Forecast Display Type",
                    "Bolus Display Threshold"
                ]
            ),
            .init(title: "Trio Statistics", rows: ["eA1c/GMI Display Unit", "Time in Range Type", "Home Statistics Panel"]),
            .init(title: "Carbs Required Badge", rows: ["Carbs Required Badge"]),
            .init(title: "Adjustments", rows: ["Require Adjustments Confirmation"])
        ],
        "Features/Treatments": [.init(title: nil, rows: ["Bolus Calculator", "Quick-Pick Treatments", "Meal Settings"])],
        "notifications": [
            .init(title: "Notification Center", rows: ["Glucose Alarms", "Device Alarms", "Day & Night Windows"]),
            .init(title: "Other Notifications", rows: ["Live Activity", "Calendar Events"])
        ],
        "services": [.init(title: "Connected Services", rows: ["Nightscout", "Apple Health"])],
        "Devices/Smart Watch": [.init(title: "Smartwatch Configuration", rows: ["Apple Watch", "Garmin"])],
        "presets": [.init(title: nil, rows: ["Overrides", "Temporary Targets", "Meals"])]
    ]

    private struct Group { let path: [String]
        let keys: [String] }

    // Paths mirror the settings modules; labels reuse the existing export/UI names.
    private static let groups: [Group] = [
        Group(
            path: ["Therapy", "Units and Limits"],
            keys: [
                "trioSettings.units",
                "preferences.maxIOB",
                "pumpSettings.maxBolus",
                "pumpSettings.maxBasal",
                "preferences.maxCOB",
                "preferences.threshold_setting",
                "trioSettings.insulinConcentration",
                "trioSettings.allowDilution"
            ]
        ),
        Group(path: ["Devices", "Continuous Glucose Monitor"], keys: ["trioSettings.smoothGlucose"]),
        Group(
            path: ["Algorithm", "Autosens"],
            keys: ["preferences.autosensMax", "preferences.autosensMin", "preferences.rewindResetsAutosens"]
        ),
        Group(
            path: ["Algorithm", "Super Micro Bolus (SMB)"],
            keys: [
                "preferences.enableSMBAlways",
                "preferences.enableSMBWithCOB",
                "preferences.enableSMBWithTemptarget",
                "preferences.enableSMBAfterCarbs",
                "preferences.enableSMB_high_bg",
                "preferences.allowSMBWithHighTemptarget",
                "preferences.enableUAM",
                "preferences.maxSMBBasalMinutes",
                "preferences.maxUAMSMBBasalMinutes",
                "preferences.maxDeltaBGthreshold",
                "preferences.enableSMB_high_bg_target"
            ]
        ),
        Group(
            path: ["Algorithm", "Dynamic Settings"],
            keys: [
                "preferences.adjustmentFactor",
                "preferences.adjustmentFactorSigmoid",
                "preferences.weightPercentage",
                "preferences.tddAdjBasal",
                "preferences.useNewFormula",
                "preferences.sigmoid",
                "preferences.useWeightedAverage"
            ]
        ),
        Group(
            path: ["Algorithm", "Target Behavior"],
            keys: [
                "preferences.highTemptargetRaisesSensitivity",
                "preferences.lowTemptargetLowersSensitivity",
                "preferences.sensitivityRaisesTarget",
                "preferences.resistanceLowersTarget",
                "preferences.halfBasalExerciseTarget",
                "preferences.advTargetAdjustments",
                "preferences.exerciseMode",
                "preferences.wideBGTargetRange"
            ]
        ),
        Group(
            path: ["Algorithm", "Additionals"],
            keys: [
                "preferences.maxDailySafetyMultiplier",
                "preferences.currentBasalSafetyMultiplier",
                "preferences.useCustomPeakTime",
                "pumpSettings.insulinActionCurve",
                "preferences.insulinPeakTime",
                "preferences.skipNeutralTemps",
                "preferences.unsuspendIfNoTemp",
                "preferences.suspendZerosIOB",
                "preferences.smbDeliveryRatio",
                "preferences.smbInterval",
                "preferences.remainingCarbsFraction",
                "preferences.remainingCarbsCap",
                "preferences.noisyCGMTargetMultiplier",
                "preferences.min5mCarbimpact",
                "preferences.curve",
                "preferences.updateInterval",
                "preferences.a52RiskEnable"
            ]
        ),
        Group(
            path: ["Features", "Treatments", "Bolus Calculator"],
            keys: [
                "trioSettings.displayPresets",
                "trioSettings.overrideFactor",
                "trioSettings.fattyMeals",
                "trioSettings.fattyMealFactor",
                "trioSettings.sweetMeals",
                "trioSettings.sweetMealFactor",
                "trioSettings.confirmBolus"
            ]
        ),
        Group(path: ["Features", "Treatments", "Quick-Pick Treatments"], keys: ["trioSettings.enableQuickPickTreatments"]),
        Group(
            path: ["Features", "Treatments", "Meal Settings"],
            keys: [
                "trioSettings.maxCarbs",
                "trioSettings.maxFat",
                "trioSettings.maxProtein",
                "preferences.maxMealAbsorptionTime",
                "trioSettings.useFPUconversion",
                "trioSettings.delay",
                "trioSettings.minuteInterval",
                "trioSettings.individualAdjustmentFactor"
            ]
        ),
        Group(path: ["Features", "Shortcuts"], keys: ["trioSettings.bolusShortcut"]),
        Group(
            path: ["Features", "User Interface"],
            keys: [
                "trioSettings.xGridLines",
                "trioSettings.yGridLines",
                "trioSettings.rulerMarks",
                "trioSettings.eA1cDisplayUnit",
                "trioSettings.showCarbsRequiredBadge",
                "trioSettings.carbsRequiredThreshold",
                "trioSettings.forecastDisplayType",
                "trioSettings.glucoseColorScheme",
                "trioSettings.timeInRangeType",
                "trioSettings.requireAdjustmentsConfirmation",
                "trioSettings.bolusDisplayThreshold",
                "trioSettings.low",
                "trioSettings.high",
                "trioSettings.homeStatsPanelFace",
                "trioSettings.showCobIobChart",
                "trioSettings.hideInsulinBadge"
            ]
        ),
        Group(path: ["Notifications", "Glucose Alarms"], keys: ["trioSettings.glucoseBadge", "preferences.carbsReqThreshold"]),
        Group(
            path: ["Notifications", "Live Activity"],
            keys: [
                "trioSettings.useLiveActivity",
                "trioSettings.lockScreenView",
                "trioSettings.displayGlucoseForecasts",
                "trioSettings.smartStackView"
            ]
        ),
        Group(path: ["Services", "Nightscout"], keys: ["trioSettings.uploadGlucose", "trioSettings.uploadCGMSensorStates"]),
        Group(path: ["Services", "Apple Health"], keys: ["trioSettings.useAppleHealth"]),
        Group(
            path: ["Notifications", "Calendar Events"],
            keys: ["trioSettings.useCalendar", "trioSettings.displayCalendarIOBandCOB", "trioSettings.displayCalendarEmojis"]
        ),
        Group(
            path: ["Devices", "Smart Watch", "Apple Watch"],
            keys: ["trioSettings.confirmBolusFaster", "trioSettings.showForecastWatch"]
        ),
        Group(
            path: ["Devices", "Smart Watch", "Garmin"],
            keys: [
                "trioSettings.garminWatchface",
                "trioSettings.garminDatafield",
                "trioSettings.primaryAttributeChoice",
                "trioSettings.secondaryAttributeChoice",
                "trioSettings.isWatchfaceDataEnabled"
            ]
        ),
        Group(path: ["Features", "App Diagnostics"], keys: ["trioSettings.debugOptions"])
    ]
    private static let paths = Dictionary(uniqueKeysWithValues: groups.flatMap { group in
        group.keys.map { ($0, group.path) }
    })
    private static let labels: [String: String] = [
        "smoothGlucose": "Smooth Glucose Value",
        "units": "Glucose Units",
        "maxIOB": "Maximum Insulin on Board (IOB)",
        "maxBolus": "Maximum Bolus",
        "maxBasal": "Maximum Basal Rate",
        "maxCOB": "Maximum Carbs on Board (COB)",
        "autosensMax": "Autosens Max",
        "autosensMin": "Autosens Min",
        "rewindResetsAutosens": "Rewind Resets Autosens",
        "enableSMBAlways": "Enable SMB Always",
        "enableSMBWithCOB": "Enable SMB With COB",
        "enableSMBWithTemptarget": "Enable SMB With Temptarget",
        "enableSMBAfterCarbs": "Enable SMB After Carbs",
        "enableSMB_high_bg": "Enable SMB With High Glucose",
        "allowSMBWithHighTemptarget": "Allow SMB With High Temptarget",
        "enableUAM": "Enable UAM",
        "maxSMBBasalMinutes": "Maximum SMB Basal Minutes",
        "maxUAMSMBBasalMinutes": "Maximum UAM SMB Basal Minutes",
        "maxDeltaBGthreshold": "Maximum Allowed Glucose Rise for SMB",
        "adjustmentFactor": "Adjustment Factor (AF)",
        "adjustmentFactorSigmoid": "Sigmoid Adjustment Factor",
        "weightPercentage": "Weighted Average of TDD",
        "tddAdjBasal": "Adjust Basal",
        "highTemptargetRaisesSensitivity": "High Temporary Target Raises Sensitivity",
        "lowTemptargetLowersSensitivity": "Low Temporary Target Lowers Sensitivity",
        "sensitivityRaisesTarget": "Sensitivity Raises Target",
        "resistanceLowersTarget": "Resistance Lowers Target",
        "maxDailySafetyMultiplier": "Max Daily Safety Multiplier",
        "currentBasalSafetyMultiplier": "Current Basal Safety Multiplier",
        "useCustomPeakTime": "Use Custom Peak Time",
        "insulinActionCurve": "Duration of Insulin Action",
        "insulinPeakTime": "Insulin Peak Time",
        "skipNeutralTemps": "Skip Neutral Temps",
        "unsuspendIfNoTemp": "Unsuspend If No Temp",
        "suspendZerosIOB": "Suspend Zeros IOB",
        "smbDeliveryRatio": "SMB Delivery Ratio",
        "smbInterval": "SMB Interval",
        "remainingCarbsFraction": "Remaining Carbs Percentage",
        "remainingCarbsCap": "Remaining Carbs Cap",
        "noisyCGMTargetMultiplier": "Noisy CGM Target Increase",
        "displayPresets": "Display Meal Presets",
        "overrideFactor": "Recommended Bolus Percentage",
        "fattyMeals": "Enable Reduced Bolus Option",
        "fattyMealFactor": "Reduced Bolus Percentage",
        "sweetMeals": "Enable Super Bolus Option",
        "sweetMealFactor": "Super Bolus Percentage",
        "confirmBolus": "Very Low Glucose Warning",
        "enableQuickPickTreatments": "Enable Quick-Pick Treatments",
        "maxCarbs": "Max Carbs",
        "maxFat": "Max Fat",
        "maxProtein": "Max Protein",
        "maxMealAbsorptionTime": "Maximum Meal Absorption Time",
        "useFPUconversion": "Enable Fat and Protein Entries",
        "delay": "Fat and Protein Delay",
        "minuteInterval": "Spread Interval",
        "individualAdjustmentFactor": "Fat and Protein Percentage",
        "bolusShortcut": "Allow Bolusing with Shortcuts",
        "xGridLines": "Show X-Axis Grid Lines",
        "yGridLines": "Show Y-Axis Grid Lines",
        "rulerMarks": "Show Low and High Thresholds",
        "eA1cDisplayUnit": "eA1c/GMI Display Unit",
        "showCarbsRequiredBadge": "Show Carbs Required Badge",
        "carbsRequiredThreshold": "Carbs Required Threshold",
        "forecastDisplayType": "Forecast Display Type",
        "glucoseColorScheme": "Glucose Color Scheme",
        "timeInRangeType": "Time in Range Type",
        "requireAdjustmentsConfirmation": "Require Adjustments Confirmation",
        "glucoseBadge": "Show Glucose App Badge",
        "useLiveActivity": "Enable Live Activity",
        "lockScreenView": "Lock Screen Widget Style",
        "displayGlucoseForecasts": "Display Glucose Forecasts",
        "uploadGlucose": "Upload Glucose",
        "uploadCGMSensorStates": "Upload CGM Sensor States",
        "useAppleHealth": "Apple Health",
        "threshold_setting": "Minimum Safety Threshold",
        "enableSMB_high_bg_target": "High Glucose Target",
        "useNewFormula": "Dynamic ISF",
        "sigmoid": "Sigmoid Formula",
        "halfBasalExerciseTarget": "Half Basal Exercise Target",
        "min5mCarbimpact": "Min 5m Carb Impact",
        "low": "Low Threshold",
        "high": "High Threshold",
        "smartStackView": "Smart Stack View",
        "homeStatsPanelFace": "Home Statistics Panel",
        "curve": "Insulin Curve",
        "useWeightedAverage": "Use Weighted Average",
        "updateInterval": "Update Interval",
        "carbsReqThreshold": "Carbs Required Threshold",
        "advTargetAdjustments": "Advanced Target Adjustments",
        "exerciseMode": "Exercise Mode",
        "wideBGTargetRange": "Wide Glucose Target Range",
        "a52RiskEnable": "A52 Risk Enable",
        "insulinConcentration": "Insulin Concentration",
        "allowDilution": "Allow Dilution",
        "target": "Glucose Target",
        "thresholdMgDL": "Glucose Threshold",
        "halfBasalTarget": "Half Basal Target",
        "overridesSilenceAndDND": "Override Silence and Do Not Disturb",
        "debugOptions": "Debug Options"
    ]
    private static let units: [String: String] = [
        "maxIOB": "U",
        "maxBolus": "U",
        "maxBasal": "U/hr",
        "maxCOB": "g",
        "autosensMax": "%",
        "autosensMin": "%",
        "maxSMBBasalMinutes": "minutes",
        "maxUAMSMBBasalMinutes": "minutes",
        "maxDeltaBGthreshold": "%",
        "weightPercentage": "%",
        "adjustmentFactor": "%",
        "adjustmentFactorSigmoid": "%",
        "maxDailySafetyMultiplier": "%",
        "currentBasalSafetyMultiplier": "%",
        "insulinActionCurve": "hours",
        "insulinPeakTime": "minutes",
        "smbDeliveryRatio": "%",
        "smbInterval": "minutes",
        "remainingCarbsFraction": "%",
        "remainingCarbsCap": "g",
        "noisyCGMTargetMultiplier": "%",
        "overrideFactor": "%",
        "fattyMealFactor": "%",
        "sweetMealFactor": "%",
        "maxCarbs": "g",
        "maxFat": "g",
        "maxProtein": "g",
        "maxMealAbsorptionTime": "hours",
        "delay": "minutes",
        "minuteInterval": "minutes",
        "individualAdjustmentFactor": "%",
        "carbsRequiredThreshold": "g",
        "updateInterval": "minutes",
        "carbsReqThreshold": "g"
    ]
    private static let glucoseFields: Set<String> = [
        "threshold_setting",
        "enableSMB_high_bg_target",
        "halfBasalExerciseTarget",
        "min5mCarbimpact",
        "low",
        "high"
    ]
    private static let excludedFields: Set<String> = [
        "dosingMode",
        "useNewFormula",
        "sigmoid",
        "bolusIncrement",
        "cgm",
        "cgmPluginIdentifier",
        "isDownloadEnabled",
        "isUploadEnabled",
        "localGlucosePort",
        "timestamp",
        "useLocalGlucoseSource"
    ]

    private struct Builder {
        let configuration: TrioSettingsBackup.Configuration
        var roots: [BackupSettingsNode] = [
            .init(id: "devices", title: "Devices", note: "Pump and CGM pairing are not included."),
            .init(id: "therapy", title: "Therapy"),
            .init(id: "algorithm", title: "Algorithm"),
            .init(id: "features", title: "Features"),
            .init(id: "notifications", title: "Notifications"),
            .init(id: "services", title: "Services", note: "Sign-in details are not included."),
            .init(
                id: "presets",
                title: "Presets",
                note: "Active overrides and temporary targets are not included."
            )
        ]

        mutating func addFields(_ value: Any, source: String) {
            for field in Mirror(reflecting: value).children {
                guard let key = field.label, !excludedFields.contains(key) else { continue }
                let identifier = source + "." + key
                let path = paths[identifier]
                    ?? (source == "preferences" ? ["Algorithm", "Additionals"] : ["Features", "User Interface"])
                var value = field.value
                var unit = units[key]
                if var decimal = value as? Decimal, type(of: value) == Decimal.self {
                    if unit == "%" { decimal *= 100 }
                    if glucoseFields.contains(key) {
                        if configuration.settings.units == .mmolL { decimal = decimal.asMmolL }
                        unit = configuration.settings.units.rawValue + (key == "min5mCarbimpact" ? "/5 min" : "")
                    }
                    value = decimal
                }
                let text = format(value) + (unit.map { " " + $0 } ?? "")
                add(.init(id: identifier, title: labels[key] ?? title(key), value: text), path: path)
            }
        }

        mutating func addSchedules() {
            let config = configuration
            let schedules = [
                Self
                    .schedule(config.basalProfile, id: "basal", title: "Basal Rates", start: \.start) { format($0.rate) + " U/hr"
                    },
                Self
                    .schedule(config.carbRatios.schedule, id: "carbs", title: "Carb Ratios", start: \.start) {
                        format($0.ratio) + (config.carbRatios.units == .grams ? " g/U" : " exchanges/U") },
                Self.schedule(
                    config.insulinSensitivities.sensitivities,
                    id: "isf",
                    title: "Insulin Sensitivities",
                    start: \.start
                ) {
                    glucose($0.sensitivity, source: config.insulinSensitivities.units) + "/U"
                },
                Self.schedule(config.glucoseTargets.targets, id: "targets", title: "Glucose Targets", start: \.start) { entry in
                    let low = glucose(entry.low, source: config.glucoseTargets.units)
                    return entry.low == entry.high ? low : low + " – " + glucose(entry.high, source: config.glucoseTargets.units)
                }
            ]
            for schedule in schedules { add(schedule, path: ["Therapy"]) }
        }

        private static func schedule<Entry>(
            _ entries: [Entry], id: String, title: String, start: KeyPath<Entry, String>, value: (Entry) -> String
        ) -> BackupSettingsNode {
            let children: [BackupSettingsNode] = entries.enumerated().map { index, entry in
                .init(id: "\(id)-\(index)", title: entry[keyPath: start].formattedHourMinuteFromTimeString(), value: value(entry))
            }
            return .init(id: id, title: title, children: children)
        }

        private func glucose(_ value: Decimal, source: GlucoseUnits) -> String {
            let destination = configuration.settings.units
            let converted = source == destination ? value : (destination == .mmolL ? value.asMmolL : value.asMgdL)
            return format(converted) + " " + destination.rawValue
        }

        mutating func addAlertPreferences(_ alerts: GlucoseAlertConfiguration) {
            add(.init(
                id: "cgmalert-preference", title: "Use CGM App Alerts", value: format(!alerts.forceTrioAlertsWhenCGMProvidesOwn)
            ), path: ["Notifications", "Glucose Alarms"])
            let children: [BackupSettingsNode] = [
                .init(
                    id: "Notifications/Day & Night Windows/dayStart",
                    title: "Day Start",
                    value: String(format: "%02d:%02d", alerts.dayStart.hour, alerts.dayStart.minute)
                ),
                .init(
                    id: "Notifications/Day & Night Windows/nightStart",
                    title: "Night Start",
                    value: String(format: "%02d:%02d", alerts.nightStart.hour, alerts.nightStart.minute)
                )
            ]
            add(
                .init(id: "Notifications/Day & Night Windows", title: "Day & Night Windows", children: children),
                path: ["Notifications"]
            )
        }

        mutating func addAlertWindowLinks() {
            guard let index = roots.firstIndex(where: { $0.id == "notifications" }),
                  let windows = roots[index].children.first(where: { $0.title == "Day & Night Windows" }) else { return }
            for child in roots[index].children.indices {
                if ["Glucose Alarms", "Device Alarms"].contains(roots[index].children[child].title) {
                    let id = roots[index].children[child].id + "/windows"
                    roots[index].children[child].children.append(.init(id: id, title: windows.title, children: windows.children))
                }
            }
        }

        mutating func addDynamicISFSetting() {
            let preferences = configuration.preferences
            let type: DynamicSettings.DynamicSensitivityType = preferences.useNewFormula
                ? (preferences.sigmoid ? .sigmoid : .logarithmic) : .disabled
            add(
                .init(id: "dynamic-isf-formula", title: "Dynamic ISF", value: type.displayName),
                path: ["Algorithm", "Dynamic Settings"]
            )
        }

        mutating func groupCompoundSettings() {
            let compounds: [(String, String, [String])] = [
                ("grid-lines", "Chart Grid Lines", ["trioSettings.xGridLines", "trioSettings.yGridLines"]),
                ("glucose-thresholds", "Glucose Thresholds", ["trioSettings.low", "trioSettings.high"]),
                (
                    "carbs-badge",
                    "Carbs Required Badge",
                    ["trioSettings.showCarbsRequiredBadge", "trioSettings.carbsRequiredThreshold"]
                ),
                ("custom-peak", "Use Custom Peak Time", ["preferences.useCustomPeakTime", "preferences.insulinPeakTime"]),
                ("reduced-bolus", "Reduced Bolus Option", ["trioSettings.fattyMeals", "trioSettings.fattyMealFactor"]),
                ("super-bolus", "Super Bolus Option", ["trioSettings.sweetMeals", "trioSettings.sweetMealFactor"]),
                (
                    "high-glucose-smb",
                    "Enable SMB With High Glucose",
                    ["preferences.enableSMB_high_bg", "preferences.enableSMB_high_bg_target"]
                )
            ]
            for (id, title, fields) in compounds { Self.combine(id: id, title: title, fields: fields, nodes: &roots) }
        }

        private static func combine(id: String, title: String, fields: [String], nodes: inout [BackupSettingsNode]) {
            for index in nodes.indices {
                let values = fields.compactMap { field in nodes[index].children.first { $0.id == field } }
                if values.count == fields.count {
                    let position = nodes[index].children.firstIndex { fields.contains($0.id) } ?? 0
                    nodes[index].children.removeAll { fields.contains($0.id) }
                    nodes[index].children.insert(
                        .init(id: id, title: title, children: values, isGroupedRow: true), at: position
                    )
                } else { combine(id: id, title: title, fields: fields, nodes: &nodes[index].children) }
            }
        }

        mutating func addHistory(_ history: [TrioSettingsBackup.TDDRecord]?) {
            var node = BackupSettingsNode(id: "tdd-history", title: "Dynamic ISF History", isGroupedRow: true)
            if let history, let newest = history.max(by: { $0.date < $1.date }),
               let oldest = history.min(by: { $0.date < $1.date })
            {
                node.children = [
                    .init(id: "history-count", title: "Saved Summaries", value: format(history.count)),
                    .init(id: "history-first", title: "First Summary", value: format(oldest.date)),
                    .init(id: "history-last", title: "Latest Summary", value: format(newest.date)),
                    .init(id: "history-total", title: "Latest Total Daily Dose", value: format(newest.total) + " U"),
                    .init(id: "history-weighted", title: "Latest Weighted Average", value: format(newest.weightedAverage) + " U"),
                    .init(id: "history-bolus", title: "Latest Bolus Total", value: format(newest.bolus) + " U"),
                    .init(id: "history-temp", title: "Latest Temporary Basal Total", value: format(newest.tempBasal) + " U"),
                    .init(id: "history-basal", title: "Latest Scheduled Basal Total", value: format(newest.scheduledBasal) + " U")
                ]
            } else {
                node.value = String(localized: "Not included")
            }
            add(node, path: ["Algorithm", "Dynamic Settings"])
        }

        mutating func addEncoded<Value: Encodable>(_ value: Value, title: String, path: [String]) {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            guard let bytes = try? encoder.encode(value),
                  let object = try? JSONSerialization.jsonObject(with: bytes) else { return }
            add(
                jsonNode(
                    object,
                    title: title,
                    id: (path + [title]).joined(separator: "/"),
                    glucoseUnits: configuration.settings.units
                ),
                path: path
            )
        }

        mutating func add(_ node: BackupSettingsNode, path: [String]) {
            Self.insert(node, into: &roots, path: path[...])
        }

        private static func insert(
            _ node: BackupSettingsNode, into nodes: inout [BackupSettingsNode], path: ArraySlice<String>,
            parentPath: [String] = []
        ) {
            guard let first = path.first else {
                if let index = nodes.firstIndex(where: { $0.id == node.id }) {
                    nodes[index].children.append(contentsOf: node.children)
                    if nodes[index].children.isEmpty { nodes[index].value = node.value }
                } else { nodes.append(node) }
                return
            }
            let fullPath = parentPath + [first]
            let index: Int
            if let existing = nodes.firstIndex(where: { $0.title == first }) { index = existing }
            else {
                nodes.append(.init(id: fullPath.joined(separator: "/"), title: first))
                index = nodes.count - 1
            }
            insert(node, into: &nodes[index].children, path: path.dropFirst(), parentPath: fullPath)
        }
    }

    private static func jsonNode(_ value: Any, title: String, id: String, glucoseUnits: GlucoseUnits) -> Self {
        if let object = value as? [String: Any] {
            if let hour = object["hour"] as? Int, let minute = object["minute"] as? Int,
               Set(object.keys) == ["hour", "minute"]
            {
                return .init(id: id, title: title, value: String(format: "%02d:%02d", hour, minute))
            }
            let hidden: Set<String> = ["id", "objectID", "snoozedUntil", "name", "dish"]
            let children = object.keys.sorted().filter { !hidden.contains($0) }.compactMap { key -> Self? in
                guard let value = object[key], !(value is NSNull) else { return nil }
                let label = labels[key] ?? Self.title(key)
                if let number = value as? NSNumber {
                    if ["target", "halfBasalTarget", "thresholdMgDL"].contains(key) {
                        if key == "thresholdMgDL", object["type"] as? String == "carbsRequired" {
                            return .init(id: id + "/" + key, title: "Carbs Required Threshold", value: format(number) + " g")
                        }
                        let converted = glucoseUnits == .mmolL ? number.decimalValue.asMmolL : number.decimalValue
                        return .init(id: id + "/" + key, title: label, value: format(converted) + " " + glucoseUnits.rawValue)
                    }
                    let unit = [
                        "percentage": "%",
                        "duration": "minutes",
                        "carbs": "g",
                        "fat": "g",
                        "protein": "g",
                        "smbMinutes": "minutes",
                        "uamMinutes": "minutes",
                        "start": "hours",
                        "end": "hours"
                    ][key]
                    if let unit { return .init(id: id + "/" + key, title: label, value: format(number) + " " + unit) }
                }
                if key == "activeOption", let raw = value as? String, let option = ActiveOption(rawValue: raw) {
                    return .init(id: id + "/" + key, title: "Active", value: option.displayName)
                }
                if key == "type", let raw = value as? String, let type = GlucoseAlertType(rawValue: raw) {
                    return .init(id: id + "/" + key, title: "Type", value: type.displayName)
                }
                return jsonNode(value, title: label, id: id + "/" + key, glucoseUnits: glucoseUnits)
            }
            return .init(id: id, title: title, children: children)
        }
        if let items = value as? [Any] {
            return .init(
                id: id,
                title: title,
                value: items.isEmpty ? String(localized: "None") : nil,
                children: items.enumerated().map { index, item in
                    let object = item as? [String: Any]
                    let name = object?["name"] as? String ?? object?["dish"] as? String
                        ?? (object?["severity"] as? String).map(Self.title) ?? "\(index + 1)"
                    var node = jsonNode(item, title: name, id: id + "/\(index)", glucoseUnits: glucoseUnits)
                    node.isGroupedRow = object != nil
                    return node
                }
            )
        }
        return .init(id: id, title: title, value: format(value))
    }

    private static func format(_ value: Any) -> String {
        if let boolean = value as? NSNumber, CFGetTypeID(boolean) == CFBooleanGetTypeID() {
            return boolean.boolValue ? String(localized: "Enabled") : String(localized: "Disabled")
        }
        if let decimal = value as? Decimal { return number(NSDecimalNumber(decimal: decimal)) }
        if let value = value as? NSNumber {
            return number(value)
        }
        if let value = value as? any RawRepresentable {
            let text = String(describing: value.rawValue)
            return text.contains("/") ? text : title(text)
        }
        if let value = value as? String { return value }
        if let value = value as? Date { return value.formatted(date: .abbreviated, time: .shortened) }
        if value is NSNull { return String(localized: "None") }
        return String(describing: value)
    }

    private static func number(_ value: NSNumber) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 8
        return formatter.string(from: value) ?? value.stringValue
    }

    private static func title(_ value: String) -> String {
        let words = value.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "([A-Z]+)([A-Z][a-z])", with: "$1 $2", options: .regularExpression)
            .replacingOccurrences(of: "([a-z0-9])([A-Z])", with: "$1 $2", options: .regularExpression)
        let acronyms = [
            "bg": "BG",
            "isf": "ISF",
            "smb": "SMB",
            "cgm": "CGM",
            "uam": "UAM",
            "cr": "CR",
            "tdd": "TDD",
            "iob": "IOB",
            "cob": "COB",
            "fpu": "FPU"
        ]
        return words.split(separator: " ").map { acronyms[$0.lowercased()] ?? $0.capitalized }.joined(separator: " ")
    }
}

struct BackupSettingsPreviewView: View {
    let node: BackupSettingsNode
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        List {
            ForEach(node.sections) { section in
                Section {
                    ForEach(section.rows) { child in
                        if child.isGroupedRow, !child.children.isEmpty {
                            groupedRow(child)
                        } else if child.children.isEmpty {
                            LabeledContent {
                                Text(child.value ?? String(localized: "None"))
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.trailing)
                                    .textSelection(.enabled)
                            } label: { Text(LocalizedStringKey(child.title)) }
                        } else {
                            NavigationLink {
                                BackupSettingsPreviewView(node: child)
                            } label: { Text(LocalizedStringKey(child.title)) }
                        }
                    }
                    if section.rows.isEmpty {
                        Text(node.value ?? String(localized: "No settings included.")).foregroundStyle(.secondary)
                    }
                } header: {
                    if let title = section.title { Text(LocalizedStringKey(title)) }
                } footer: {
                    if section.id == node.sections.last?.id, let note = node.note { Text(LocalizedStringKey(note)) }
                }.listRowBackground(Color.chart)
            }
        }
        .listSectionSpacing(sectionSpacing)
        .scrollContentBackground(.hidden)
        .background(appState.trioBackgroundColor(for: colorScheme))
        .navigationTitle(Text(LocalizedStringKey(node.navigationTitle)))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func groupedRow(_ item: BackupSettingsNode) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(LocalizedStringKey(item.title)).fontWeight(.semibold)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(item.children) { field in
                    LabeledContent {
                        Text(field.value ?? String(localized: "None")).multilineTextAlignment(.trailing)
                    } label: { Text(LocalizedStringKey(field.title)) }
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .textSelection(.enabled)
    }
}
