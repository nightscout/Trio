import CoreData
import Foundation
import LoopKit
import SwiftUI
import Swinject

extension Export {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() private var broadcaster: Broadcaster!
        @Injected() private var fileManager: FileManager!
        @Injected() private var storage: FileStorage!
        @Injected() var overrideStorage: OverrideStorage!

        // Version information
        private var versionNumber: String = ""
        private var buildNumber: String = ""
        private var branch: String = ""

        override func subscribe() {
            versionNumber = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
            buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
            branch = BuildDetails.shared.branchAndSha
        }

        // Export categories for selective export
        enum ExportCategory: String, CaseIterable, Identifiable {
            case exportInfo = "Export Info"
            case devices = "Devices"
            case therapy = "Therapy"
            case algorithm = "Algorithm"
            case features = "Features"
            case notifications = "Notifications"
            case services = "Services"
            case presets = "Presets"

            var id: String { rawValue }

            var description: String {
                switch self {
                case .exportInfo:
                    return "Date, app version, build information"
                case .devices:
                    return "CGM and pump configuration"
                case .therapy:
                    return "Basal profiles, ISF, carb ratios, targets"
                case .algorithm:
                    return "SMB, autosens, dynamic settings"
                case .features:
                    return "UI preferences, meal settings"
                case .notifications:
                    return "Alert and notification settings"
                case .services:
                    return "Nightscout, Apple Health integration"
                case .presets:
                    return "Temp targets, overrides, meal presets"
                }
            }
        }

        // Published state for UI binding
        @Published var selectedCategories: Set<ExportCategory> = Set(ExportCategory.allCases)

        enum ExportError: LocalizedError {
            case documentsDirectoryNotFound
            case fileWriteError(Error)
            case unknown(String)

            var errorDescription: String? {
                switch self {
                case .documentsDirectoryNotFound:
                    return String(localized: "Could not access documents directory")
                case let .fileWriteError(error):
                    return String(localized: "Failed to write export file: \(error.localizedDescription)")
                case let .unknown(message):
                    return String(localized: "Export failed: \(message)")
                }
            }
        }

        /// Exports selected Trio settings to a CSV file
        ///
        /// This function creates an export of the user's selected Trio configuration categories including:
        /// - Export metadata (date, app version, build) [optional]
        /// - Device settings (CGM, pump information) [optional]
        /// - Therapy profiles (basal rates, ISF, carb ratios, targets) [optional]
        /// - Algorithm settings (SMB, autosens, dynamic settings, etc.) [optional]
        /// - Features and UI preferences [optional]
        /// - Notification settings [optional]
        /// - Service configurations [optional]
        /// - Preset data [optional]
        ///
        /// - Parameter categories: Set of categories to include in export. If nil, exports all categories.
        /// - Returns: A Result containing either the file URL on success or an ExportError on failure
        func exportSettings(categories: Set<ExportCategory>? = nil) async -> Result<URL, ExportError> {
            debug(.default, "Starting settings export...")

            let categoriesToExport = categories ?? selectedCategories
            debug(.default, "Exporting categories: \(categoriesToExport.map(\.rawValue).joined(separator: ", "))")

            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd_HHmmss"
            let timestamp = formatter.string(from: Date())
            let fileName = "TrioSettings_\(timestamp).csv"

            // Use the temporary directory for better sharing compatibility
            let tempDirectory = FileManager.default.temporaryDirectory
            let fileURL = tempDirectory.appendingPathComponent(fileName)
            debug(.default, "Export file path: \(fileURL.path)")

            var csvContent = "Setting Category,Subcategory,Setting Name,Value,Unit\n"

            let trioSettings = settingsManager.settings
            let preferences = settingsManager.preferences

            // Export metadata - always include basic export info
            if categoriesToExport.contains(.exportInfo) {
                let exportCategory = String(localized: "Export Info")
                addSetting(
                    category: exportCategory,
                    name: String(localized: "Export Date"),
                    value: DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .medium)
                )
                addSetting(category: exportCategory, name: String(localized: "App Version"), value: versionNumber)
                addSetting(category: exportCategory, name: String(localized: "Build Number"), value: buildNumber)
                addSetting(category: exportCategory, name: String(localized: "Branch"), value: branch)
            }

            // Helper function to escape CSV values
            func csvEscape(_ value: String) -> String {
                if value.contains(",") || value.contains("\"") || value.contains("\n") {
                    return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
                }
                return value
            }

            // Helper function to add a setting row
            func addSetting(category: String, subcategory: String = "", name: String, value: String, unit: String = "") {
                csvContent +=
                    "\(csvEscape(category)),\(csvEscape(subcategory)),\(csvEscape(name)),\(csvEscape(value)),\(csvEscape(unit))\n"
            }

            // Helper function to add a separator row
            func addSeparator(title: String = "") {
                csvContent += "\n=== \(title.isEmpty ? "SECTION SEPARATOR" : title.uppercased()) ===,,,,\n\n"
            }

            // Helper function to add a subseparator for individual items
            func addSubSeparator(title: String) {
                csvContent += "\n--- \(title) ---,,,,\n"
            }

            // Devices
            if categoriesToExport.contains(.devices) {
                let devicesCategory = String(localized: "Devices", comment: "Devices menu item in the Settings main view.")
                addSetting(category: devicesCategory, name: String(localized: "CGM"), value: trioSettings.cgm.rawValue)
                addSetting(
                    category: devicesCategory,
                    name: String(localized: "Smooth Glucose Value"),
                    value: trioSettings.smoothGlucose ? String(localized: "Enabled") : String(localized: "Disabled")
                )
                // Pump Information
                if let pumpManager = provider.deviceManager.pumpManager {
                    addSetting(category: devicesCategory, name: String(localized: "Pump Type"), value: pumpManager.localizedTitle)
                } else {
                    addSetting(category: devicesCategory, name: String(localized: "Pump Type"), value: "Not Connected")
                }
            }

            // Therapy Settings
            if categoriesToExport.contains(.therapy) {
                let therapyCategory = String(localized: "Therapy", comment: "Therapy menu item in the Settings main view.")
                addSetting(
                    category: therapyCategory,
                    name: String(localized: "Glucose Units"),
                    value: trioSettings.units.rawValue
                )
                addSetting(
                    category: therapyCategory,
                    name: String(localized: "Max IOB"),
                    value: String(describing: preferences.maxIOB),
                    unit: "U"
                )
                addSetting(
                    category: therapyCategory,
                    name: String(localized: "Max COB"),
                    value: String(describing: preferences.maxCOB),
                    unit: "g"
                )

                // Get therapy profiles from storage
                let basalProfile = storage.retrieve(OpenAPS.Settings.basalProfile, as: [BasalProfileEntry].self) ?? []
                let isfProfileContainer = storage.retrieve(OpenAPS.Settings.insulinSensitivities, as: InsulinSensitivities.self)
                let crProfileContainer = storage.retrieve(OpenAPS.Settings.carbRatios, as: CarbRatios.self)
                let targetProfileContainer = storage.retrieve(OpenAPS.Settings.bgTargets, as: BGTargets.self)

                // Export therapy profiles
                let therapyProfilesSubcategory = String(localized: "Therapy Profiles")

                // Basal Profile
                for entry in basalProfile {
                    addSetting(
                        category: therapyCategory,
                        subcategory: therapyProfilesSubcategory,
                        name: "Basal Rate (\(entry.start))",
                        value: String(describing: entry.rate),
                        unit: "U/hr"
                    )
                }

                // ISF Profile
                if let isfContainer = isfProfileContainer {
                    for entry in isfContainer.sensitivities {
                        let isfValue = trioSettings.units == .mgdL ? entry.sensitivity : entry.sensitivity.asMmolL
                        addSetting(
                            category: therapyCategory,
                            subcategory: therapyProfilesSubcategory,
                            name: "ISF (\(entry.start))",
                            value: String(describing: isfValue),
                            unit: trioSettings.units == .mgdL ? "mg/dL/U" : "mmol/L/U"
                        )
                    }
                }

                // Carb Ratio Profile
                if let crContainer = crProfileContainer {
                    for entry in crContainer.schedule {
                        addSetting(
                            category: therapyCategory,
                            subcategory: therapyProfilesSubcategory,
                            name: "Carb Ratio (\(entry.start))",
                            value: String(describing: entry.ratio),
                            unit: "g/U"
                        )
                    }
                }

                // Target Profile
                if let targetContainer = targetProfileContainer {
                    for entry in targetContainer.targets {
                        let lowValue = trioSettings.units == .mgdL ? entry.low : entry.low.asMmolL
                        let highValue = trioSettings.units == .mgdL ? entry.high : entry.high.asMmolL
                        addSetting(
                            category: therapyCategory,
                            subcategory: therapyProfilesSubcategory,
                            name: "Target Low (\(entry.start))",
                            value: String(describing: lowValue),
                            unit: trioSettings.units.rawValue
                        )
                        addSetting(
                            category: therapyCategory,
                            subcategory: therapyProfilesSubcategory,
                            name: "Target High (\(entry.start))",
                            value: String(describing: highValue),
                            unit: trioSettings.units.rawValue
                        )
                    }
                }
            }

            // Algorithm Settings
            if categoriesToExport.contains(.algorithm) {
                let algorithmCategory = String(localized: "Algorithm", comment: "Algorithm menu item in the Settings main view.")

                // Autosens Settings
                let autosensSubcategory = String(localized: "Autosens")
                addSetting(
                    category: algorithmCategory,
                    subcategory: autosensSubcategory,
                    name: String(localized: "Autosens Max"),
                    value: String(describing: preferences.autosensMax)
                )
                addSetting(
                    category: algorithmCategory,
                    subcategory: autosensSubcategory,
                    name: String(localized: "Autosens Min"),
                    value: String(describing: preferences.autosensMin)
                )
                addSetting(
                    category: algorithmCategory,
                    subcategory: autosensSubcategory,
                    name: String(localized: "Rewind Resets Autosens"),
                    value: preferences.rewindResetsAutosens ? String(localized: "Enabled") : String(localized: "Disabled")
                )

                // SMB Settings
                let smbSubcategory = String(localized: "SMB")
                addSetting(
                    category: algorithmCategory,
                    subcategory: smbSubcategory,
                    name: String(localized: "Enable SMB Always"),
                    value: preferences.enableSMBAlways ? String(localized: "Enabled") : String(localized: "Disabled")
                )
                addSetting(
                    category: algorithmCategory,
                    subcategory: smbSubcategory,
                    name: String(localized: "Enable SMB With COB"),
                    value: preferences.enableSMBWithCOB ? String(localized: "Enabled") : String(localized: "Disabled")
                )
                addSetting(
                    category: algorithmCategory,
                    subcategory: smbSubcategory,
                    name: String(localized: "Enable SMB With Temporary Target"),
                    value: preferences.enableSMBWithTemptarget ? String(localized: "Enabled") : String(localized: "Disabled")
                )
                addSetting(
                    category: algorithmCategory,
                    subcategory: smbSubcategory,
                    name: String(localized: "Enable SMB After Carbs"),
                    value: preferences.enableSMBAfterCarbs ? String(localized: "Enabled") : String(localized: "Disabled")
                )
                addSetting(
                    category: algorithmCategory,
                    subcategory: smbSubcategory,
                    name: String(localized: "Enable UAM"),
                    value: preferences.enableUAM ? String(localized: "Enabled") : String(localized: "Disabled")
                )
                addSetting(
                    category: algorithmCategory,
                    subcategory: smbSubcategory,
                    name: String(localized: "Max SMB Basal Minutes"),
                    value: String(describing: preferences.maxSMBBasalMinutes),
                    unit: String(localized: "minutes")
                )
                addSetting(
                    category: algorithmCategory,
                    subcategory: smbSubcategory,
                    name: String(localized: "Max UAM SMB Basal Minutes"),
                    value: String(describing: preferences.maxUAMSMBBasalMinutes),
                    unit: String(localized: "minutes")
                )
                addSetting(
                    category: algorithmCategory,
                    subcategory: smbSubcategory,
                    name: String(localized: "SMB Delivery Ratio"),
                    value: String(describing: preferences.smbDeliveryRatio)
                )
                addSetting(
                    category: algorithmCategory,
                    subcategory: smbSubcategory,
                    name: String(localized: "SMB Interval"),
                    value: String(describing: preferences.smbInterval),
                    unit: String(localized: "minutes")
                )

                // Dynamic Settings
                let dynamicSubcategory = String(localized: "Dynamic Settings")
                addSetting(
                    category: algorithmCategory,
                    subcategory: dynamicSubcategory,
                    name: String(localized: "Dynamic ISF"),
                    value: preferences.useNewFormula ? String(localized: "Enabled") : String(localized: "Disabled")
                )
                addSetting(
                    category: algorithmCategory,
                    subcategory: dynamicSubcategory,
                    name: String(localized: "Sigmoid"),
                    value: preferences.sigmoid ? String(localized: "Enabled") : String(localized: "Disabled")
                )
                addSetting(
                    category: algorithmCategory,
                    subcategory: dynamicSubcategory,
                    name: String(localized: "Adjustment Factor (AF)"),
                    value: String(describing: preferences.adjustmentFactor)
                )
                addSetting(
                    category: algorithmCategory,
                    subcategory: dynamicSubcategory,
                    name: String(localized: "Sigmoid Adjustment Factor"),
                    value: String(describing: preferences.adjustmentFactorSigmoid)
                )
                addSetting(
                    category: algorithmCategory,
                    subcategory: dynamicSubcategory,
                    name: String(localized: "Weighted Average of TDD"),
                    value: preferences.useWeightedAverage ? String(localized: "Enabled") : String(localized: "Disabled")
                )
                addSetting(
                    category: algorithmCategory,
                    subcategory: dynamicSubcategory,
                    name: String(localized: "Adjust Basal"),
                    value: preferences.tddAdjBasal ? String(localized: "Enabled") : String(localized: "Disabled")
                )

                // Target Behavior
                let targetBehaviorSubcategory = String(localized: "Target Behavior")
                addSetting(
                    category: algorithmCategory,
                    subcategory: targetBehaviorSubcategory,
                    name: String(localized: "High Temptarget Raises Sensitivity"),
                    value: preferences
                        .highTemptargetRaisesSensitivity ? String(localized: "Enabled") : String(localized: "Disabled")
                )
                addSetting(
                    category: algorithmCategory,
                    subcategory: targetBehaviorSubcategory,
                    name: String(localized: "Low Temptarget Lowers Sensitivity"),
                    value: preferences
                        .lowTemptargetLowersSensitivity ? String(localized: "Enabled") : String(localized: "Disabled")
                )
                addSetting(
                    category: algorithmCategory,
                    subcategory: targetBehaviorSubcategory,
                    name: String(localized: "Sensitivity Raises Target"),
                    value: preferences.sensitivityRaisesTarget ? String(localized: "Enabled") : String(localized: "Disabled")
                )
                addSetting(
                    category: algorithmCategory,
                    subcategory: targetBehaviorSubcategory,
                    name: String(localized: "Resistance Lowers Target"),
                    value: preferences.resistanceLowersTarget ? String(localized: "Enabled") : String(localized: "Disabled")
                )
                addSetting(
                    category: algorithmCategory,
                    subcategory: targetBehaviorSubcategory,
                    name: String(localized: "Half Basal Exercise Target"),
                    value: trioSettings
                        .units == .mgdL ? String(describing: preferences.halfBasalExerciseTarget) :
                        String(describing: preferences.halfBasalExerciseTarget.asMmolL),
                    unit: trioSettings.units.rawValue
                )

                // Additional Algorithm Settings
                let additionalsSubcategory = String(localized: "Additionals")
                addSetting(
                    category: algorithmCategory,
                    subcategory: additionalsSubcategory,
                    name: String(localized: "Max Daily Safety Multiplier"),
                    value: String(describing: preferences.maxDailySafetyMultiplier)
                )
                addSetting(
                    category: algorithmCategory,
                    subcategory: additionalsSubcategory,
                    name: String(localized: "Current Basal Safety Multiplier"),
                    value: String(describing: preferences.currentBasalSafetyMultiplier)
                )
                addSetting(
                    category: algorithmCategory,
                    subcategory: additionalsSubcategory,
                    name: String(localized: "Use Custom Peak Time"),
                    value: preferences.useCustomPeakTime ? String(localized: "Enabled") : String(localized: "Disabled")
                )
                addSetting(
                    category: algorithmCategory,
                    subcategory: additionalsSubcategory,
                    name: String(localized: "Insulin Peak Time"),
                    value: String(describing: preferences.insulinPeakTime),
                    unit: String(localized: "minutes")
                )
                addSetting(
                    category: algorithmCategory,
                    subcategory: additionalsSubcategory,
                    name: String(localized: "Skip Neutral Temps"),
                    value: preferences.skipNeutralTemps ? String(localized: "Enabled") : String(localized: "Disabled")
                )
                addSetting(
                    category: algorithmCategory,
                    subcategory: additionalsSubcategory,
                    name: String(localized: "Unsuspend If No Temp"),
                    value: preferences.unsuspendIfNoTemp ? String(localized: "Enabled") : String(localized: "Disabled")
                )
                addSetting(
                    category: algorithmCategory,
                    subcategory: additionalsSubcategory,
                    name: String(localized: "Suspend Zeros IOB"),
                    value: preferences.suspendZerosIOB ? String(localized: "Enabled") : String(localized: "Disabled")
                )
                addSetting(
                    category: algorithmCategory,
                    subcategory: additionalsSubcategory,
                    name: String(localized: "Min 5m Carb Impact"),
                    value: trioSettings
                        .units == .mgdL ? String(describing: preferences.min5mCarbimpact) :
                        String(describing: preferences.min5mCarbimpact.asMmolL),
                    unit: trioSettings.units == .mgdL ? "mg/dL" : "mmol/L"
                )
                addSetting(
                    category: algorithmCategory,
                    subcategory: additionalsSubcategory,
                    name: String(localized: "Remaining Carbs Fraction"),
                    value: String(describing: preferences.remainingCarbsFraction)
                )
                addSetting(
                    category: algorithmCategory,
                    subcategory: additionalsSubcategory,
                    name: String(localized: "Remaining Carbs Cap"),
                    value: String(describing: preferences.remainingCarbsCap),
                    unit: "g"
                )
                addSetting(
                    category: algorithmCategory,
                    subcategory: additionalsSubcategory,
                    name: String(localized: "Noisy CGM Target Multiplier"),
                    value: String(describing: preferences.noisyCGMTargetMultiplier)
                )
                addSetting(
                    category: algorithmCategory,
                    subcategory: additionalsSubcategory,
                    name: String(localized: "Duration of Insulin Action (DIA)"),
                    value: String(describing: preferences.insulinActionCurve),
                    unit: String(localized: "hours")
                )
            }

            // Features
            if categoriesToExport.contains(.features) {
                let featuresCategory = String(localized: "Features", comment: "Features menu item in the Settings main view.")

                // Meal Settings
                addSetting(
                    category: featuresCategory,
                    name: String(localized: "Max Carbs"),
                    value: String(describing: trioSettings.maxCarbs),
                    unit: "g"
                )
                addSetting(
                    category: featuresCategory,
                    name: String(localized: "Max Fat"),
                    value: String(describing: trioSettings.maxFat),
                    unit: "g"
                )
                addSetting(
                    category: featuresCategory,
                    name: String(localized: "Max Protein"),
                    value: String(describing: trioSettings.maxProtein),
                    unit: "g"
                )
                addSetting(
                    category: featuresCategory,
                    name: String(localized: "Display and Allow Fat and Protein Entries"),
                    value: trioSettings.useFPUconversion ? String(localized: "Enabled") : String(localized: "Disabled")
                )
                addSetting(
                    category: featuresCategory,
                    name: String(localized: "Fat and Protein Factor"),
                    value: String(describing: trioSettings.individualAdjustmentFactor)
                )
                addSetting(
                    category: featuresCategory,
                    name: String(localized: "Maximum Duration (hours)"),
                    value: String(describing: trioSettings.timeCap),
                    unit: String(localized: "hours")
                )
                addSetting(
                    category: featuresCategory,
                    name: String(localized: "Spread Interval (minutes)"),
                    value: String(describing: trioSettings.minuteInterval),
                    unit: String(localized: "minutes")
                )
                addSetting(
                    category: featuresCategory,
                    name: String(localized: "Fat and Protein Delay"),
                    value: String(describing: trioSettings.delay),
                    unit: String(localized: "minutes")
                )

                // User Interface
                addSetting(
                    category: featuresCategory,
                    name: String(localized: "Show X-Axis Grid Lines"),
                    value: trioSettings.xGridLines ? String(localized: "Enabled") : String(localized: "Disabled")
                )
                addSetting(
                    category: featuresCategory,
                    name: String(localized: "Show Y-Axis Grid Lines"),
                    value: trioSettings.yGridLines ? String(localized: "Enabled") : String(localized: "Disabled")
                )
                addSetting(
                    category: featuresCategory,
                    name: String(localized: "Show Low and High Thresholds"),
                    value: trioSettings.rulerMarks ? String(localized: "Enabled") : String(localized: "Disabled")
                )
                addSetting(
                    category: featuresCategory,
                    name: String(localized: "Low Threshold"),
                    value: trioSettings
                        .units == .mgdL ? String(describing: trioSettings.low) : String(describing: trioSettings.low.asMmolL),
                    unit: trioSettings.units.rawValue
                )
                addSetting(
                    category: featuresCategory,
                    name: String(localized: "High Threshold"),
                    value: trioSettings
                        .units == .mgdL ? String(describing: trioSettings.high) : String(describing: trioSettings.high.asMmolL),
                    unit: trioSettings.units.rawValue
                )
                addSetting(
                    category: featuresCategory,
                    name: String(localized: "eA1c/GMI Display Unit"),
                    value: trioSettings.eA1cDisplayUnit.rawValue
                )
                addSetting(
                    category: featuresCategory,
                    name: String(localized: "Show Carbs Required Badge"),
                    value: trioSettings.showCarbsRequiredBadge ? String(localized: "Enabled") : String(localized: "Disabled")
                )
                addSetting(
                    category: featuresCategory,
                    name: String(localized: "Carbs Required Threshold"),
                    value: String(describing: trioSettings.carbsRequiredThreshold),
                    unit: "g"
                )
                addSetting(
                    category: featuresCategory,
                    name: String(localized: "Forecast Display Type"),
                    value: trioSettings.forecastDisplayType.rawValue
                )
                addSetting(
                    category: featuresCategory,
                    name: String(localized: "Glucose Color Scheme"),
                    value: trioSettings.glucoseColorScheme.rawValue
                )
                addSetting(
                    category: featuresCategory,
                    name: String(localized: "Time in Range Type"),
                    value: trioSettings.timeInRangeType.rawValue
                )
            }

            // Notifications
            if categoriesToExport.contains(.notifications) {
                let notificationsCategory = String(
                    localized: "Notifications",
                    comment: "Notifications menu item in the Settings main view."
                )
                addSetting(
                    category: notificationsCategory,
                    name: String(localized: "Always Notify Pump"),
                    value: trioSettings.notificationsPump ? String(localized: "Enabled") : String(localized: "Disabled")
                )
                addSetting(
                    category: notificationsCategory,
                    name: String(localized: "Always Notify CGM"),
                    value: trioSettings.notificationsCgm ? String(localized: "Enabled") : String(localized: "Disabled")
                )
                addSetting(
                    category: notificationsCategory,
                    name: String(localized: "Always Notify Carb"),
                    value: trioSettings.notificationsCarb ? String(localized: "Enabled") : String(localized: "Disabled")
                )
                addSetting(
                    category: notificationsCategory,
                    name: String(localized: "Always Notify Algorithm"),
                    value: trioSettings.notificationsAlgorithm ? String(localized: "Enabled") : String(localized: "Disabled")
                )
                addSetting(
                    category: notificationsCategory,
                    name: String(localized: "Show Glucose App Badge"),
                    value: trioSettings.glucoseBadge ? String(localized: "Enabled") : String(localized: "Disabled")
                )
                addSetting(
                    category: notificationsCategory,
                    name: String(localized: "Glucose Notifications"),
                    value: trioSettings.glucoseNotificationsOption.rawValue
                )
                addSetting(
                    category: notificationsCategory,
                    name: String(localized: "Add Glucose Source to Alarm"),
                    value: trioSettings
                        .addSourceInfoToGlucoseNotifications ? String(localized: "Enabled") : String(localized: "Disabled")
                )
                addSetting(
                    category: notificationsCategory,
                    name: String(localized: "Low Glucose Alarm Limit"),
                    value: trioSettings
                        .units == .mgdL ? String(describing: trioSettings.lowGlucose) :
                        String(describing: trioSettings.lowGlucose.asMmolL),
                    unit: trioSettings.units.rawValue
                )
                addSetting(
                    category: notificationsCategory,
                    name: String(localized: "High Glucose Alarm Limit"),
                    value: trioSettings
                        .units == .mgdL ? String(describing: trioSettings.highGlucose) :
                        String(describing: trioSettings.highGlucose.asMmolL),
                    unit: trioSettings.units.rawValue
                )
                addSetting(
                    category: notificationsCategory,
                    name: String(localized: "Enable Live Activity"),
                    value: trioSettings.useLiveActivity ? String(localized: "Enabled") : String(localized: "Disabled")
                )
                addSetting(
                    category: notificationsCategory,
                    name: String(localized: "Lock Screen Widget Style"),
                    value: trioSettings.lockScreenView.rawValue
                )
            }

            // Services
            if categoriesToExport.contains(.services) {
                let servicesCategory = String(localized: "Services", comment: "Services menu item in the Settings main view.")
                addSetting(
                    category: servicesCategory,
                    name: String(localized: "Allow Uploading to Nightscout"),
                    value: trioSettings.isUploadEnabled ? String(localized: "Enabled") : String(localized: "Disabled")
                )
                addSetting(
                    category: servicesCategory,
                    name: String(localized: "Upload Glucose"),
                    value: trioSettings.uploadGlucose ? String(localized: "Enabled") : String(localized: "Disabled")
                )
                addSetting(
                    category: servicesCategory,
                    name: String(localized: "Allow Fetching From Nightscout"),
                    value: trioSettings.isDownloadEnabled ? String(localized: "Enabled") : String(localized: "Disabled")
                )
                addSetting(
                    category: servicesCategory,
                    name: String(localized: "Apple Health"),
                    value: trioSettings.useAppleHealth ? String(localized: "Enabled") : String(localized: "Disabled")
                )
            }

            // Presets
            if categoriesToExport.contains(.presets) {
                let presetsCategory = String(localized: "Presets")

                // Temp Target Presets
                let tempTargetPresets = storage.retrieve(OpenAPS.Trio.tempTargetsPresets, as: [TempTarget].self) ?? []
                if !tempTargetPresets.isEmpty {
                    let tempTargetSubcategory = String(localized: "Temp Target Presets")
                    for preset in tempTargetPresets {
                        // Add separator for each temp target preset
                        addSubSeparator(title: "Temp Target: \(preset.displayName)")

                        let targetTopValue = trioSettings.units == .mgdL ? (preset.targetTop ?? 0) : (preset.targetTop ?? 0)
                            .asMmolL
                        addSetting(
                            category: presetsCategory,
                            subcategory: tempTargetSubcategory,
                            name: preset.displayName,
                            value: String(describing: targetTopValue),
                            unit: trioSettings.units.rawValue
                        )
                        addSetting(
                            category: presetsCategory,
                            subcategory: tempTargetSubcategory,
                            name: "\(preset.displayName) Duration",
                            value: String(describing: preset.duration),
                            unit: String(localized: "minutes")
                        )

                        // Add targetBottom if different from targetTop
                        if let targetBottom = preset.targetBottom, targetBottom != preset.targetTop {
                            let targetBottomValue = trioSettings.units == .mgdL ? targetBottom : targetBottom.asMmolL
                            addSetting(
                                category: presetsCategory,
                                subcategory: tempTargetSubcategory,
                                name: "\(preset.displayName) Target Bottom",
                                value: String(describing: targetBottomValue),
                                unit: trioSettings.units.rawValue
                            )
                        }

                        // Add halfBasalTarget if set
                        if let halfBasalTarget = preset.halfBasalTarget {
                            let halfBasalValue = trioSettings.units == .mgdL ? halfBasalTarget : halfBasalTarget.asMmolL
                            addSetting(
                                category: presetsCategory,
                                subcategory: tempTargetSubcategory,
                                name: "\(preset.displayName) Half Basal Target",
                                value: String(describing: halfBasalValue),
                                unit: trioSettings.units.rawValue
                            )
                        }

                        // Add reason if different from name
                        if let reason = preset.reason, reason != preset.name {
                            addSetting(
                                category: presetsCategory,
                                subcategory: tempTargetSubcategory,
                                name: "\(preset.displayName) Reason",
                                value: reason
                            )
                        }

                        // Add enteredBy
                        if let enteredBy = preset.enteredBy {
                            addSetting(
                                category: presetsCategory,
                                subcategory: tempTargetSubcategory,
                                name: "\(preset.displayName) Entered By",
                                value: enteredBy
                            )
                        }
                    }
                }

                // Add separator between temp targets and override presets
                addSeparator(title: "Override Presets")

                // Override Presets (from Core Data)
                do {
                    debug(.default, "Fetching override presets...")

                    // Ensure Core Data is fully initialized - wait longer on first run
                    var retryCount = 0
                    var overridePresetIDs: [NSManagedObjectID] = []

                    while retryCount < 3 {
                        do {
                            overridePresetIDs = try await overrideStorage.fetchForOverridePresets()
                            break // Success, exit retry loop
                        } catch {
                            debug(.default, "Attempt \(retryCount + 1) failed: \(error)")
                            retryCount += 1
                            if retryCount < 3 {
                                // Wait progressively longer between retries
                                do {
                                    try await Task.sleep(nanoseconds: UInt64(retryCount * 200_000_000)) // 0.2s, 0.4s
                                } catch {
                                    // Sleep interrupted, continue
                                }
                            }
                        }
                    }

                    debug(.default, "Found \(overridePresetIDs.count) override preset IDs")
                    if !overridePresetIDs.isEmpty {
                        let overrideSubcategory = String(localized: "Override Presets")

                        // Convert NSManagedObjectIDs to actual OverrideStored objects and extract their data within the Core Data context
                        // Add a small delay to ensure Core Data is ready, especially on first app launch
                        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 second

                        let viewContext = CoreDataStack.shared.persistentContainer.viewContext
                        let presetData = try await viewContext.perform {
                            overridePresetIDs
                                .compactMap { id -> (
                                    name: String,
                                    percentage: Double,
                                    indefinite: Bool,
                                    duration: Decimal?,
                                    target: Decimal?,
                                    advancedSettings: Bool,
                                    cr: Bool,
                                    isf: Bool,
                                    isfAndCr: Bool,
                                    smbIsOff: Bool,
                                    smbIsScheduledOff: Bool,
                                    start: Decimal?,
                                    end: Decimal?,
                                    smbMinutes: Decimal?,
                                    uamMinutes: Decimal?
                                )? in
                                do {
                                    guard let preset = try viewContext.existingObject(with: id) as? OverrideStored else {
                                        debug(.default, "Could not retrieve override with ID: \(id)")
                                        return nil
                                    }
                                    return (
                                        name: preset.name ?? "Unknown Override",
                                        percentage: preset.percentage,
                                        indefinite: preset.indefinite,
                                        duration: preset.duration?.decimalValue,
                                        target: preset.target?.decimalValue,
                                        advancedSettings: preset.advancedSettings,
                                        cr: preset.cr,
                                        isf: preset.isf,
                                        isfAndCr: preset.isfAndCr,
                                        smbIsOff: preset.smbIsOff,
                                        smbIsScheduledOff: preset.smbIsScheduledOff,
                                        start: preset.start?.decimalValue,
                                        end: preset.end?.decimalValue,
                                        smbMinutes: preset.smbMinutes?.decimalValue,
                                        uamMinutes: preset.uamMinutes?.decimalValue
                                    )
                                } catch {
                                    debug(.default, "Error accessing override preset: \(error)")
                                    return nil
                                }
                                }
                        }

                        debug(.default, "Successfully extracted \(presetData.count) override presets")

                        for preset in presetData {
                            // Add separator for each override preset
                            addSubSeparator(title: "Override: \(preset.name)")

                            addSetting(
                                category: presetsCategory,
                                subcategory: overrideSubcategory,
                                name: preset.name,
                                value: String(format: "%.0f%%", preset.percentage)
                            )
                            addSetting(
                                category: presetsCategory,
                                subcategory: overrideSubcategory,
                                name: "\(preset.name) Duration",
                                value: preset
                                    .indefinite ? String(localized: "Indefinite") : String(describing: preset.duration ?? 0),
                                unit: preset.indefinite ? "" : String(localized: "minutes")
                            )
                            if let target = preset.target, target != 0 {
                                let targetValue = trioSettings.units == .mgdL ? target : target.asMmolL
                                addSetting(
                                    category: presetsCategory,
                                    subcategory: overrideSubcategory,
                                    name: "\(preset.name) Target",
                                    value: String(describing: targetValue),
                                    unit: trioSettings.units.rawValue
                                )
                            }

                            // Advanced settings
                            if preset.advancedSettings {
                                addSetting(
                                    category: presetsCategory,
                                    subcategory: overrideSubcategory,
                                    name: "\(preset.name) Advanced Settings",
                                    value: String(localized: "Enabled")
                                )
                                if let smbMinutes = preset.smbMinutes {
                                    addSetting(
                                        category: presetsCategory,
                                        subcategory: overrideSubcategory,
                                        name: "\(preset.name) SMB Minutes",
                                        value: String(describing: smbMinutes),
                                        unit: String(localized: "minutes")
                                    )
                                }
                                if let uamMinutes = preset.uamMinutes {
                                    addSetting(
                                        category: presetsCategory,
                                        subcategory: overrideSubcategory,
                                        name: "\(preset.name) UAM Minutes",
                                        value: String(describing: uamMinutes),
                                        unit: String(localized: "minutes")
                                    )
                                }
                            }

                            // SMB settings
                            if preset.smbIsOff {
                                addSetting(
                                    category: presetsCategory,
                                    subcategory: overrideSubcategory,
                                    name: "\(preset.name) SMB",
                                    value: String(localized: "Disabled")
                                )
                            }

                            if preset.smbIsScheduledOff {
                                addSetting(
                                    category: presetsCategory,
                                    subcategory: overrideSubcategory,
                                    name: "\(preset.name) SMB Scheduled",
                                    value: String(localized: "Disabled")
                                )
                                if let start = preset.start {
                                    addSetting(
                                        category: presetsCategory,
                                        subcategory: overrideSubcategory,
                                        name: "\(preset.name) SMB Schedule Start",
                                        value: String(describing: start),
                                        unit: String(localized: "hours")
                                    )
                                }
                                if let end = preset.end {
                                    addSetting(
                                        category: presetsCategory,
                                        subcategory: overrideSubcategory,
                                        name: "\(preset.name) SMB Schedule End",
                                        value: String(describing: end),
                                        unit: String(localized: "hours")
                                    )
                                }
                            }

                            // Sensitivity settings
                            if preset.isfAndCr {
                                addSetting(
                                    category: presetsCategory,
                                    subcategory: overrideSubcategory,
                                    name: "\(preset.name) Affects",
                                    value: String(localized: "ISF and CR")
                                )
                            } else if preset.isf, preset.cr {
                                addSetting(
                                    category: presetsCategory,
                                    subcategory: overrideSubcategory,
                                    name: "\(preset.name) Affects",
                                    value: String(localized: "ISF and CR")
                                )
                            } else if preset.isf {
                                addSetting(
                                    category: presetsCategory,
                                    subcategory: overrideSubcategory,
                                    name: "\(preset.name) Affects",
                                    value: String(localized: "ISF")
                                )
                            } else if preset.cr {
                                addSetting(
                                    category: presetsCategory,
                                    subcategory: overrideSubcategory,
                                    name: "\(preset.name) Affects",
                                    value: String(localized: "CR")
                                )
                            }
                        }
                    }
                } catch {
                    debug(.default, "Failed to fetch override presets: \(error)")
                }

                // Add separator for meal presets
                addSeparator(title: "Meal Presets")

                // Meal Presets (from Core Data)
                do {
                    debug(.default, "Fetching meal presets...")
                    let viewContext = CoreDataStack.shared.persistentContainer.viewContext

                    let mealPresetData = try await viewContext.perform {
                        let request: NSFetchRequest<MealPresetStored> = MealPresetStored.fetchRequest()
                        let mealPresets = try viewContext.fetch(request)

                        return mealPresets.map { preset -> (dish: String, carbs: Decimal?, fat: Decimal?, protein: Decimal?) in
                            (
                                dish: preset.dish ?? "Unknown Meal",
                                carbs: preset.carbs?.decimalValue,
                                fat: preset.fat?.decimalValue,
                                protein: preset.protein?.decimalValue
                            )
                        }
                    }

                    debug(.default, "Found \(mealPresetData.count) meal presets")

                    if !mealPresetData.isEmpty {
                        let mealPresetSubcategory = String(localized: "Meal Presets")

                        for mealPreset in mealPresetData {
                            // Add separator for each meal preset
                            addSubSeparator(title: "Meal: \(mealPreset.dish)")

                            addSetting(
                                category: presetsCategory,
                                subcategory: mealPresetSubcategory,
                                name: mealPreset.dish,
                                value: String(localized: "Meal Preset")
                            )

                            if let carbs = mealPreset.carbs, carbs > 0 {
                                addSetting(
                                    category: presetsCategory,
                                    subcategory: mealPresetSubcategory,
                                    name: "\(mealPreset.dish) Carbs",
                                    value: String(describing: carbs),
                                    unit: "g"
                                )
                            }

                            if let fat = mealPreset.fat, fat > 0 {
                                addSetting(
                                    category: presetsCategory,
                                    subcategory: mealPresetSubcategory,
                                    name: "\(mealPreset.dish) Fat",
                                    value: String(describing: fat),
                                    unit: "g"
                                )
                            }

                            if let protein = mealPreset.protein, protein > 0 {
                                addSetting(
                                    category: presetsCategory,
                                    subcategory: mealPresetSubcategory,
                                    name: "\(mealPreset.dish) Protein",
                                    value: String(describing: protein),
                                    unit: "g"
                                )
                            }
                        }
                    }
                } catch {
                    debug(.default, "Failed to fetch meal presets: \(error)")
                }
            }

            // Add final separator after presets section
            addSeparator(title: "End of Export")

            // Write to file
            do {
                debug(.default, "Writing CSV content (\(csvContent.count) characters) to file...")
                try csvContent.write(to: fileURL, atomically: true, encoding: .utf8)

                // Set file attributes for better sharing compatibility
                try fileManager.setAttributes([
                    .posixPermissions: 0o644,
                    .extensionHidden: false
                ], ofItemAtPath: fileURL.path)

                // Verify file was written successfully
                let fileExists = fileManager.fileExists(atPath: fileURL.path)
                debug(.default, "File written successfully. Exists: \(fileExists)")

                if !fileExists {
                    debug(.default, "File was not created at expected location: \(fileURL.path)")
                    return .failure(.unknown("File was not created successfully"))
                }

                return .success(fileURL)
            } catch {
                debug(.default, "Failed to write settings export file: \(error)")
                return .failure(.fileWriteError(error))
            }
        }

        /// Exports settings using the currently selected categories
        func exportSelectedSettings() async -> Result<URL, ExportError> {
            await exportSettings(categories: selectedCategories)
        }

        /// Toggle all categories on or off
        func toggleAllCategories(_ enabled: Bool) {
            if enabled {
                selectedCategories = Set(ExportCategory.allCases)
            } else {
                selectedCategories = []
            }
        }

        /// Check if all categories are selected
        var allCategoriesSelected: Bool {
            selectedCategories.count == ExportCategory.allCases.count
        }
    }
}
