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
        @Injected() var tempTargetsStorage: TempTargetsStorage!

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
            case tempTargetPresets = "Temp Target Presets"
            case overridePresets = "Override Presets"
            case mealPresets = "Meal Presets"

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
                case .tempTargetPresets:
                    return "Exercise, eating soon, and custom temp targets"
                case .overridePresets:
                    return "Sensitivity adjustments and insulin factor overrides"
                case .mealPresets:
                    return "Saved meal configurations with carbs, fat, and protein"
                }
            }
        }

        // Export formats for different file types
        enum ExportFormat: String, CaseIterable, Identifiable {
            case csv = "CSV"
            case json = "JSON"

            var id: String { rawValue }

            var description: String {
                switch self {
                case .csv:
                    return "Comma-separated values format, compatible with spreadsheets"
                case .json:
                    return "JavaScript Object Notation format, structured data"
                }
            }

            var fileExtension: String {
                switch self {
                case .csv:
                    return "csv"
                case .json:
                    return "json"
                }
            }
        }

        // Published state for UI binding
        @Published var selectedCategories: Set<ExportCategory> = Set(ExportCategory.allCases)
        @Published var selectedFormat: ExportFormat = .csv
        @Published var isExporting: Bool = false

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
        /// - Parameter format: Export format to use. If nil, uses currently selected format.
        /// - Returns: A Result containing either the file URL on success or an ExportError on failure
        func exportSettings(
            categories: Set<ExportCategory>? = nil,
            format: ExportFormat? = nil
        ) async -> Result<URL, ExportError> {
            debug(.default, "🔄 EXPORT: Starting settings export...")

            let categoriesToExport = categories ?? selectedCategories
            let exportFormat = format ?? selectedFormat
            debug(
                .default,
                "🔄 EXPORT: Exporting categories: \(categoriesToExport.map(\.rawValue).joined(separator: ", ")) in \(exportFormat.rawValue) format"
            )

            debug(
                .default,
                "🔄 EXPORT: CoreData stack status - persistentContainer: \(CoreDataStack.shared.persistentContainer.description)"
            )
            debug(.default, "🔄 EXPORT: ViewContext status: \(CoreDataStack.shared.persistentContainer.viewContext.description)")

            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd_HHmmss"
            let timestamp = formatter.string(from: Date())
            let fileName = "TrioSettings_\(timestamp).\(exportFormat.fileExtension)"

            // Use the Documents directory for better sharing compatibility
            guard let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
                return .failure(.documentsDirectoryNotFound)
            }
            let fileURL = documentsDirectory.appendingPathComponent(fileName)
            debug(.default, "Export file path: \(fileURL.path)")

            // Data structure to hold export data
            struct ExportSetting {
                let category: String
                let subcategory: String
                let name: String
                let value: String
                let unit: String

                init(category: String, subcategory: String = "", name: String, value: String, unit: String = "") {
                    self.category = category
                    self.subcategory = subcategory
                    self.name = name
                    self.value = value
                    self.unit = unit
                }
            }

            var exportSettings: [ExportSetting] = []

            let trioSettings = settingsManager.settings
            let preferences = settingsManager.preferences
            debug(.default, "🔄 EXPORT: Settings managers initialized")

            // Helper function to add a setting
            func addSetting(category: String, subcategory: String = "", name: String, value: String, unit: String = "") {
                exportSettings.append(ExportSetting(
                    category: category,
                    subcategory: subcategory,
                    name: name,
                    value: value,
                    unit: unit
                ))
            }

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

                // Units and Limits subcategory
                let unitsLimitsSubcategory = String(localized: "Units and Limits")
                addSetting(
                    category: therapyCategory,
                    subcategory: unitsLimitsSubcategory,
                    name: String(localized: "Glucose Units"),
                    value: trioSettings.units.rawValue
                )
                addSetting(
                    category: therapyCategory,
                    subcategory: unitsLimitsSubcategory,
                    name: String(localized: "Maximum Insulin on Board (IOB)"),
                    value: String(describing: preferences.maxIOB),
                    unit: "U"
                )

                // Add missing pump settings from PumpSettings
                let pumpSettings = settingsManager.pumpSettings
                addSetting(
                    category: therapyCategory,
                    subcategory: unitsLimitsSubcategory,
                    name: String(localized: "Maximum Bolus"),
                    value: String(describing: pumpSettings.maxBolus),
                    unit: "U"
                )
                addSetting(
                    category: therapyCategory,
                    subcategory: unitsLimitsSubcategory,
                    name: String(localized: "Maximum Basal Rate"),
                    value: String(describing: pumpSettings.maxBasal),
                    unit: "U/hr"
                )
                // Get insulin type from pump manager if available, otherwise from preferences
                let insulinTypeValue: String
                if let pumpManager = provider.deviceManager.pumpManager,
                   let insulinType = pumpManager.status.insulinType
                {
                    insulinTypeValue = insulinType.title
                } else {
                    insulinTypeValue = preferences.curve.rawValue
                }
                addSetting(
                    category: therapyCategory,
                    subcategory: unitsLimitsSubcategory,
                    name: String(localized: "Insulin Type"),
                    value: insulinTypeValue
                )
                addSetting(
                    category: therapyCategory,
                    subcategory: unitsLimitsSubcategory,
                    name: String(localized: "Maximum Carbs on Board (COB)"),
                    value: String(describing: preferences.maxCOB),
                    unit: "g"
                )
                addSetting(
                    category: therapyCategory,
                    subcategory: unitsLimitsSubcategory,
                    name: String(localized: "Minimum Safety Threshold"),
                    value: trioSettings
                        .units == .mgdL ? String(describing: preferences.threshold_setting) :
                        String(describing: preferences.threshold_setting.asMmolL),
                    unit: trioSettings.units.rawValue
                )

                // Get therapy profiles from storage
                let basalProfile = storage.retrieve(OpenAPS.Settings.basalProfile, as: [BasalProfileEntry].self) ?? []
                let isfProfileContainer = storage.retrieve(OpenAPS.Settings.insulinSensitivities, as: InsulinSensitivities.self)
                let crProfileContainer = storage.retrieve(OpenAPS.Settings.carbRatios, as: CarbRatios.self)
                let targetProfileContainer = storage.retrieve(OpenAPS.Settings.bgTargets, as: BGTargets.self)

                // Glucose Targets subcategory
                let glucoseTargetsSubcategory = String(localized: "Glucose Targets")
                if let targetContainer = targetProfileContainer {
                    for entry in targetContainer.targets {
                        // Export single target value since high==low in Trio
                        let targetValue = trioSettings.units == .mgdL ? entry.low : entry.low.asMmolL
                        addSetting(
                            category: therapyCategory,
                            subcategory: glucoseTargetsSubcategory,
                            name: "Target (\(entry.start))",
                            value: String(describing: targetValue),
                            unit: trioSettings.units.rawValue
                        )
                    }
                }

                // Basal Rates subcategory
                let basalRatesSubcategory = String(localized: "Basal Rates")
                for entry in basalProfile {
                    addSetting(
                        category: therapyCategory,
                        subcategory: basalRatesSubcategory,
                        name: "Basal Rate (\(entry.start))",
                        value: String(describing: entry.rate),
                        unit: "U/hr"
                    )
                }

                // Carb Ratios subcategory
                let carbRatiosSubcategory = String(localized: "Carb Ratios")
                if let crContainer = crProfileContainer {
                    for entry in crContainer.schedule {
                        addSetting(
                            category: therapyCategory,
                            subcategory: carbRatiosSubcategory,
                            name: "Carb Ratio (\(entry.start))",
                            value: String(describing: entry.ratio),
                            unit: "g/U"
                        )
                    }
                }

                // Insulin Sensitivities subcategory
                let insulinSensitivitiesSubcategory = String(localized: "Insulin Sensitivities")
                if let isfContainer = isfProfileContainer {
                    for entry in isfContainer.sensitivities {
                        let isfValue = trioSettings.units == .mgdL ? entry.sensitivity : entry.sensitivity.asMmolL
                        addSetting(
                            category: therapyCategory,
                            subcategory: insulinSensitivitiesSubcategory,
                            name: "ISF (\(entry.start))",
                            value: String(describing: isfValue),
                            unit: trioSettings.units == .mgdL ? "mg/dL/U" : "mmol/L/U"
                        )
                    }
                }
            }

            // Algorithm Settings
            if categoriesToExport.contains(.algorithm) {
                let algorithmCategory = String(localized: "Algorithm", comment: "Algorithm menu item in the Settings main view.")
                let pumpSettings = settingsManager.pumpSettings

                // Autosens Settings
                let autosensSubcategory = String(localized: "Autosens")
                addSetting(
                    category: algorithmCategory,
                    subcategory: autosensSubcategory,
                    name: String(localized: "Autosens Max"),
                    value: String(format: "%.0f", (preferences.autosensMax as NSDecimalNumber).doubleValue * 100),
                    unit: "%"
                )
                addSetting(
                    category: algorithmCategory,
                    subcategory: autosensSubcategory,
                    name: String(localized: "Autosens Min"),
                    value: String(format: "%.0f", (preferences.autosensMin as NSDecimalNumber).doubleValue * 100),
                    unit: "%"
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
                    name: String(localized: "Enable SMB With Temptarget"),
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
                    name: String(localized: "Enable SMB With High Glucose"),
                    value: preferences.enableSMB_high_bg ? String(localized: "Enabled") : String(localized: "Disabled")
                )
                if preferences.enableSMB_high_bg {
                    addSetting(
                        category: algorithmCategory,
                        subcategory: smbSubcategory,
                        name: String(localized: "High Glucose Target"),
                        value: trioSettings
                            .units == .mgdL ? String(describing: preferences.enableSMB_high_bg_target) :
                            String(describing: preferences.enableSMB_high_bg_target.asMmolL),
                        unit: trioSettings.units.rawValue
                    )
                }
                addSetting(
                    category: algorithmCategory,
                    subcategory: smbSubcategory,
                    name: String(localized: "Allow SMB With High Temptarget"),
                    value: preferences.allowSMBWithHighTemptarget ? String(localized: "Enabled") : String(localized: "Disabled")
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
                    name: String(localized: "Max UAM Basal Minutes"),
                    value: String(describing: preferences.maxUAMSMBBasalMinutes),
                    unit: String(localized: "minutes")
                )
                addSetting(
                    category: algorithmCategory,
                    subcategory: smbSubcategory,
                    name: String(localized: "Max. Allowed Glucose Rise for SMB"),
                    value: String(format: "%.0f", (preferences.maxDeltaBGthreshold as NSDecimalNumber).doubleValue * 100),
                    unit: "%"
                )

                // Dynamic Settings
                let dynamicSubcategory = String(localized: "Dynamic Settings")

                // Proper Dynamic ISF handling using the current enum logic
                let dynamicISFValue: String
                if !preferences.useNewFormula {
                    dynamicISFValue = String(localized: "Disabled")
                } else if preferences.sigmoid {
                    dynamicISFValue = String(localized: "Sigmoid")
                } else {
                    dynamicISFValue = String(localized: "Logarithmic")
                }
                addSetting(
                    category: algorithmCategory,
                    subcategory: dynamicSubcategory,
                    name: String(localized: "Dynamic ISF"),
                    value: dynamicISFValue
                )

                // Show adjustment factors as percentages with proper labels
                if preferences.useNewFormula {
                    if !preferences.sigmoid {
                        addSetting(
                            category: algorithmCategory,
                            subcategory: dynamicSubcategory,
                            name: String(localized: "Adjustment Factor (AF)"),
                            value: String(format: "%.0f", (preferences.adjustmentFactor as NSDecimalNumber).doubleValue * 100),
                            unit: "%"
                        )
                    } else {
                        addSetting(
                            category: algorithmCategory,
                            subcategory: dynamicSubcategory,
                            name: String(localized: "Sigmoid Adjustment Factor"),
                            value: String(
                                format: "%.0f",
                                (preferences.adjustmentFactorSigmoid as NSDecimalNumber).doubleValue * 100
                            ),
                            unit: "%"
                        )
                    }
                }

                // Weighted Average of TDD is shown for both logarithmic and sigmoid when Dynamic ISF is enabled
                addSetting(
                    category: algorithmCategory,
                    subcategory: dynamicSubcategory,
                    name: String(localized: "Weighted Average of TDD"),
                    value: String(format: "%.0f", (preferences.weightPercentage as NSDecimalNumber).doubleValue * 100),
                    unit: "%"
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
                    value: String(format: "%.0f", (preferences.maxDailySafetyMultiplier as NSDecimalNumber).doubleValue * 100),
                    unit: "%"
                )
                addSetting(
                    category: algorithmCategory,
                    subcategory: additionalsSubcategory,
                    name: String(localized: "Current Basal Safety Multiplier"),
                    value: String(
                        format: "%.0f",
                        (preferences.currentBasalSafetyMultiplier as NSDecimalNumber).doubleValue * 100
                    ),
                    unit: "%"
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
                    name: String(localized: "Duration of Insulin Action"),
                    value: String(describing: pumpSettings.insulinActionCurve),
                    unit: String(localized: "hours")
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
                // SMB settings that belong in Additionals (correct order based on UI)
                addSetting(
                    category: algorithmCategory,
                    subcategory: additionalsSubcategory,
                    name: String(localized: "SMB Delivery Ratio"),
                    value: String(format: "%.0f", (preferences.smbDeliveryRatio as NSDecimalNumber).doubleValue * 100),
                    unit: "%"
                )
                addSetting(
                    category: algorithmCategory,
                    subcategory: additionalsSubcategory,
                    name: String(localized: "SMB Interval"),
                    value: String(describing: preferences.smbInterval),
                    unit: String(localized: "minutes")
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
                    name: String(localized: "Remaining Carbs Percentage"),
                    value: String(format: "%.0f", (preferences.remainingCarbsFraction as NSDecimalNumber).doubleValue * 100),
                    unit: "%"
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
                    name: String(localized: "Noisy CGM Target Increase"),
                    value: String(format: "%.0f", (preferences.noisyCGMTargetMultiplier as NSDecimalNumber).doubleValue * 100),
                    unit: "%"
                )
            }

            // Features
            if categoriesToExport.contains(.features) {
                let featuresCategory = String(localized: "Features", comment: "Features menu item in the Settings main view.")

                // Trio Features subcategory - Bolus Calculator
                let trioFeaturesSubcategory = String(localized: "Trio Features")
                let bolusCalculatorSubcategory = String(localized: "Bolus Calculator")
                addSetting(
                    category: featuresCategory,
                    subcategory: bolusCalculatorSubcategory,
                    name: String(localized: "Display Meal Presets"),
                    value: trioSettings.displayPresets ? String(localized: "Enabled") : String(localized: "Disabled")
                )
                addSetting(
                    category: featuresCategory,
                    subcategory: bolusCalculatorSubcategory,
                    name: String(localized: "Recommended Bolus Percentage"),
                    value: String(format: "%.0f", (trioSettings.overrideFactor as NSDecimalNumber).doubleValue * 100),
                    unit: "%"
                )
                addSetting(
                    category: featuresCategory,
                    subcategory: bolusCalculatorSubcategory,
                    name: String(localized: "Enable Reduced Bolus Option"),
                    value: trioSettings.fattyMeals ? String(localized: "Enabled") : String(localized: "Disabled")
                )
                if trioSettings.fattyMeals {
                    addSetting(
                        category: featuresCategory,
                        subcategory: bolusCalculatorSubcategory,
                        name: String(localized: "Reduced Bolus Percentage"),
                        value: String(format: "%.0f", (trioSettings.fattyMealFactor as NSDecimalNumber).doubleValue * 100),
                        unit: "%"
                    )
                }
                addSetting(
                    category: featuresCategory,
                    subcategory: bolusCalculatorSubcategory,
                    name: String(localized: "Enable Super Bolus Option"),
                    value: trioSettings.sweetMeals ? String(localized: "Enabled") : String(localized: "Disabled")
                )
                if trioSettings.sweetMeals {
                    addSetting(
                        category: featuresCategory,
                        subcategory: bolusCalculatorSubcategory,
                        name: String(localized: "Super Bolus Percentage"),
                        value: String(format: "%.0f", (trioSettings.sweetMealFactor as NSDecimalNumber).doubleValue * 100),
                        unit: "%"
                    )
                }
                addSetting(
                    category: featuresCategory,
                    subcategory: bolusCalculatorSubcategory,
                    name: String(localized: "Very Low Glucose Warning"),
                    value: trioSettings.confirmBolus ? String(localized: "Enabled") : String(localized: "Disabled")
                )

                // Trio Features subcategory - Meal Settings
                let mealSettingsSubcategory = String(localized: "Meal Settings")
                addSetting(
                    category: featuresCategory,
                    subcategory: mealSettingsSubcategory,
                    name: String(localized: "Max Carbs"),
                    value: String(describing: trioSettings.maxCarbs),
                    unit: "g"
                )
                addSetting(
                    category: featuresCategory,
                    subcategory: mealSettingsSubcategory,
                    name: String(localized: "Max Fat"),
                    value: String(describing: trioSettings.maxFat),
                    unit: "g"
                )
                addSetting(
                    category: featuresCategory,
                    subcategory: mealSettingsSubcategory,
                    name: String(localized: "Max Protein"),
                    value: String(describing: trioSettings.maxProtein),
                    unit: "g"
                )
                addSetting(
                    category: featuresCategory,
                    subcategory: mealSettingsSubcategory,
                    name: String(localized: "Max Meal Absorption Time"),
                    value: String(describing: preferences.maxMealAbsorptionTime),
                    unit: String(localized: "hours")
                )
                addSetting(
                    category: featuresCategory,
                    subcategory: mealSettingsSubcategory,
                    name: String(localized: "Enable Fat and Protein Entries"),
                    value: trioSettings.useFPUconversion ? String(localized: "Enabled") : String(localized: "Disabled")
                )
                addSetting(
                    category: featuresCategory,
                    subcategory: mealSettingsSubcategory,
                    name: String(localized: "Fat and Protein Delay"),
                    value: String(describing: trioSettings.delay),
                    unit: String(localized: "minutes")
                )
                addSetting(
                    category: featuresCategory,
                    subcategory: mealSettingsSubcategory,
                    name: String(localized: "Maximum Duration"),
                    value: String(describing: trioSettings.timeCap),
                    unit: String(localized: "hours")
                )
                addSetting(
                    category: featuresCategory,
                    subcategory: mealSettingsSubcategory,
                    name: String(localized: "Spread Interval"),
                    value: String(describing: trioSettings.minuteInterval),
                    unit: String(localized: "minutes")
                )
                addSetting(
                    category: featuresCategory,
                    subcategory: mealSettingsSubcategory,
                    name: String(localized: "Fat and Protein Percentage"),
                    value: String(format: "%.0f", (trioSettings.individualAdjustmentFactor as NSDecimalNumber).doubleValue * 100),
                    unit: "%"
                )

                // Trio Features subcategory - Shortcuts
                let shortcutsSubcategory = String(localized: "Shortcuts")
                addSetting(
                    category: featuresCategory,
                    subcategory: shortcutsSubcategory,
                    name: String(localized: "Allow Bolusing with Shortcuts"),
                    value: trioSettings
                        .bolusShortcut != .notAllowed ? String(localized: "Enabled") : String(localized: "Disabled")
                )

                // Trio Features subcategory - Remote Control
                let remoteControlSubcategory = String(localized: "Remote Control")
                let isRemoteControlEnabled = UserDefaults.standard.bool(forKey: "isTrioRemoteControlEnabled")
                addSetting(
                    category: featuresCategory,
                    subcategory: remoteControlSubcategory,
                    name: String(localized: "Enable Remote Control"),
                    value: isRemoteControlEnabled ? String(localized: "Enabled") : String(localized: "Disabled")
                )

                // Trio Personalization subcategory - User Interface
                let trioPersonalizationSubcategory = String(localized: "Trio Personalization")
                let userInterfaceSubcategory = String(localized: "User Interface")
                addSetting(
                    category: featuresCategory,
                    subcategory: userInterfaceSubcategory,
                    name: String(localized: "Show X-Axis Grid Lines"),
                    value: trioSettings.xGridLines ? String(localized: "Enabled") : String(localized: "Disabled")
                )
                addSetting(
                    category: featuresCategory,
                    subcategory: userInterfaceSubcategory,
                    name: String(localized: "Show Y-Axis Grid Lines"),
                    value: trioSettings.yGridLines ? String(localized: "Enabled") : String(localized: "Disabled")
                )
                addSetting(
                    category: featuresCategory,
                    subcategory: userInterfaceSubcategory,
                    name: String(localized: "Show Low and High Thresholds"),
                    value: trioSettings.rulerMarks ? String(localized: "Enabled") : String(localized: "Disabled")
                )
                addSetting(
                    category: featuresCategory,
                    subcategory: userInterfaceSubcategory,
                    name: String(localized: "Low Threshold"),
                    value: trioSettings
                        .units == .mgdL ? String(describing: trioSettings.low) : String(describing: trioSettings.low.asMmolL),
                    unit: trioSettings.units.rawValue
                )
                addSetting(
                    category: featuresCategory,
                    subcategory: userInterfaceSubcategory,
                    name: String(localized: "High Threshold"),
                    value: trioSettings
                        .units == .mgdL ? String(describing: trioSettings.high) : String(describing: trioSettings.high.asMmolL),
                    unit: trioSettings.units.rawValue
                )
                addSetting(
                    category: featuresCategory,
                    subcategory: userInterfaceSubcategory,
                    name: String(localized: "eA1c/GMI Display Unit"),
                    value: trioSettings.eA1cDisplayUnit.rawValue
                )
                addSetting(
                    category: featuresCategory,
                    subcategory: userInterfaceSubcategory,
                    name: String(localized: "Show Carbs Required Badge"),
                    value: trioSettings.showCarbsRequiredBadge ? String(localized: "Enabled") : String(localized: "Disabled")
                )
                addSetting(
                    category: featuresCategory,
                    subcategory: userInterfaceSubcategory,
                    name: String(localized: "Carbs Required Threshold"),
                    value: String(describing: trioSettings.carbsRequiredThreshold),
                    unit: "g"
                )
                addSetting(
                    category: featuresCategory,
                    subcategory: userInterfaceSubcategory,
                    name: String(localized: "Forecast Display Type"),
                    value: trioSettings.forecastDisplayType.rawValue
                )
                addSetting(
                    category: featuresCategory,
                    subcategory: userInterfaceSubcategory,
                    name: String(localized: "Glucose Color Scheme"),
                    value: trioSettings.glucoseColorScheme.rawValue
                )
                addSetting(
                    category: featuresCategory,
                    subcategory: userInterfaceSubcategory,
                    name: String(localized: "Time in Range Type"),
                    value: trioSettings.timeInRangeType.rawValue
                )

                // Appearance setting from UserDefaults
                let colorSchemePreference = UserDefaults.standard.string(forKey: "colorSchemePreference") ?? "systemDefault"
                let appearanceValue: String
                switch colorSchemePreference {
                case "systemDefault":
                    appearanceValue = String(localized: "System Default")
                case "light":
                    appearanceValue = String(localized: "Light")
                case "dark":
                    appearanceValue = String(localized: "Dark")
                default:
                    appearanceValue = String(localized: "System Default")
                }
                addSetting(
                    category: featuresCategory,
                    subcategory: userInterfaceSubcategory,
                    name: String(localized: "Appearance"),
                    value: appearanceValue
                )
            }

            // Notifications
            if categoriesToExport.contains(.notifications) {
                let notificationsCategory = String(
                    localized: "Notifications",
                    comment: "Notifications menu item in the Settings main view."
                )

                // Trio Notifications subcategory
                let trioNotificationsSubcategory = String(localized: "Trio Notifications")
                addSetting(
                    category: notificationsCategory,
                    subcategory: trioNotificationsSubcategory,
                    name: String(localized: "Always Notify Pump"),
                    value: trioSettings.notificationsPump ? String(localized: "Enabled") : String(localized: "Disabled")
                )
                addSetting(
                    category: notificationsCategory,
                    subcategory: trioNotificationsSubcategory,
                    name: String(localized: "Always Notify CGM"),
                    value: trioSettings.notificationsCgm ? String(localized: "Enabled") : String(localized: "Disabled")
                )
                addSetting(
                    category: notificationsCategory,
                    subcategory: trioNotificationsSubcategory,
                    name: String(localized: "Always Notify Carb"),
                    value: trioSettings.notificationsCarb ? String(localized: "Enabled") : String(localized: "Disabled")
                )
                addSetting(
                    category: notificationsCategory,
                    subcategory: trioNotificationsSubcategory,
                    name: String(localized: "Always Notify Algorithm"),
                    value: trioSettings.notificationsAlgorithm ? String(localized: "Enabled") : String(localized: "Disabled")
                )
                addSetting(
                    category: notificationsCategory,
                    subcategory: trioNotificationsSubcategory,
                    name: String(localized: "Show Glucose App Badge"),
                    value: trioSettings.glucoseBadge ? String(localized: "Enabled") : String(localized: "Disabled")
                )
                addSetting(
                    category: notificationsCategory,
                    subcategory: trioNotificationsSubcategory,
                    name: String(localized: "Glucose Notifications"),
                    value: trioSettings.glucoseNotificationsOption.rawValue
                )
                addSetting(
                    category: notificationsCategory,
                    subcategory: trioNotificationsSubcategory,
                    name: String(localized: "Add Glucose Source to Alarm"),
                    value: trioSettings
                        .addSourceInfoToGlucoseNotifications ? String(localized: "Enabled") : String(localized: "Disabled")
                )
                addSetting(
                    category: notificationsCategory,
                    subcategory: trioNotificationsSubcategory,
                    name: String(localized: "Low Glucose Alarm Limit"),
                    value: trioSettings
                        .units == .mgdL ? String(describing: trioSettings.lowGlucose) :
                        String(describing: trioSettings.lowGlucose.asMmolL),
                    unit: trioSettings.units.rawValue
                )
                addSetting(
                    category: notificationsCategory,
                    subcategory: trioNotificationsSubcategory,
                    name: String(localized: "High Glucose Alarm Limit"),
                    value: trioSettings
                        .units == .mgdL ? String(describing: trioSettings.highGlucose) :
                        String(describing: trioSettings.highGlucose.asMmolL),
                    unit: trioSettings.units.rawValue
                )

                // Live Activity subcategory
                let liveActivitySubcategory = String(localized: "Live Activity")
                addSetting(
                    category: notificationsCategory,
                    subcategory: liveActivitySubcategory,
                    name: String(localized: "Enable Live Activity"),
                    value: trioSettings.useLiveActivity ? String(localized: "Enabled") : String(localized: "Disabled")
                )
                addSetting(
                    category: notificationsCategory,
                    subcategory: liveActivitySubcategory,
                    name: String(localized: "Lock Screen Widget Style"),
                    value: trioSettings.lockScreenView.rawValue
                )
            }

            // Services
            if categoriesToExport.contains(.services) {
                let servicesCategory = String(localized: "Services", comment: "Services menu item in the Settings main view.")

                // Nightscout subcategory
                let nightscoutSubcategory = String(localized: "Nightscout")
                addSetting(
                    category: servicesCategory,
                    subcategory: nightscoutSubcategory,
                    name: String(localized: "Allow Uploading to Nightscout"),
                    value: trioSettings.isUploadEnabled ? String(localized: "Enabled") : String(localized: "Disabled")
                )
                addSetting(
                    category: servicesCategory,
                    subcategory: nightscoutSubcategory,
                    name: String(localized: "Upload Glucose"),
                    value: trioSettings.uploadGlucose ? String(localized: "Enabled") : String(localized: "Disabled")
                )
                addSetting(
                    category: servicesCategory,
                    subcategory: nightscoutSubcategory,
                    name: String(localized: "Allow Fetching From Nightscout"),
                    value: trioSettings.isDownloadEnabled ? String(localized: "Enabled") : String(localized: "Disabled")
                )

                // Apple Health subcategory
                let appleHealthSubcategory = String(localized: "Apple Health")
                addSetting(
                    category: servicesCategory,
                    subcategory: appleHealthSubcategory,
                    name: String(localized: "Apple Health"),
                    value: trioSettings.useAppleHealth ? String(localized: "Enabled") : String(localized: "Disabled")
                )
            }

            // Temp Target Presets
            if categoriesToExport.contains(.tempTargetPresets) {
                let presetsCategory = String(localized: "Temp Target Presets")

                // Temp Target Presets (from Core Data)
                debug(.default, "🔄 EXPORT: Fetching temp target presets...")
                let tempTargetPresetIDs = (try? await tempTargetsStorage.fetchForTempTargetPresets()) ?? []
                debug(.default, "🔄 EXPORT: Found \(tempTargetPresetIDs.count) temp target preset IDs")

                if !tempTargetPresetIDs.isEmpty {
                    let tempTargetSubcategory = String(localized: "Temp Target Presets")
                    let viewContext = CoreDataStack.shared.persistentContainer.viewContext

                    let presetData = await viewContext.perform {
                        tempTargetPresetIDs.compactMap { id -> (
                            name: String,
                            target: Decimal?,
                            duration: Decimal?,
                            halfBasalTarget: Decimal?
                        )? in
                        guard let preset = try? viewContext.existingObject(with: id) as? TempTargetStored else {
                            debug(.default, "Could not retrieve temp target with ID: \(id)")
                            return nil
                        }
                        return (
                            name: preset.name ?? "Unknown Temp Target",
                            target: preset.target?.decimalValue,
                            duration: preset.duration?.decimalValue,
                            halfBasalTarget: preset.halfBasalTarget?.decimalValue
                        )
                        }
                    }

                    debug(.default, "Successfully extracted \(presetData.count) temp target presets")

                    for preset in presetData {
                        if let target = preset.target {
                            let targetValue = trioSettings.units == .mgdL ? target : target.asMmolL
                            addSetting(
                                category: presetsCategory,
                                subcategory: tempTargetSubcategory,
                                name: preset.name,
                                value: String(describing: targetValue),
                                unit: trioSettings.units.rawValue
                            )
                        }

                        if let duration = preset.duration {
                            addSetting(
                                category: presetsCategory,
                                subcategory: tempTargetSubcategory,
                                name: "\(preset.name) Duration",
                                value: String(describing: duration),
                                unit: String(localized: "minutes")
                            )
                        }

                        if let halfBasalTarget = preset.halfBasalTarget {
                            let halfBasalValue = trioSettings.units == .mgdL ? halfBasalTarget : halfBasalTarget.asMmolL
                            addSetting(
                                category: presetsCategory,
                                subcategory: tempTargetSubcategory,
                                name: "\(preset.name) Half Basal Target",
                                value: String(describing: halfBasalValue),
                                unit: trioSettings.units.rawValue
                            )
                        }
                    }
                }
            }

            // Override Presets
            if categoriesToExport.contains(.overridePresets) {
                let presetsCategory = String(localized: "Override Presets")

                // Override Presets (from Core Data)
                do {
                    debug(.default, "🔄 EXPORT: Fetching override presets...")
                    debug(.default, "🔄 EXPORT: OverrideStorage instance: \(overrideStorage)")

                    // Ensure Core Data is fully initialized - wait longer on first run
                    var retryCount = 0
                    var overridePresetIDs: [NSManagedObjectID] = []

                    while retryCount < 3 {
                        do {
                            debug(.default, "🔄 EXPORT: Attempt \(retryCount + 1) to fetch override presets...")
                            overridePresetIDs = try await overrideStorage.fetchForOverridePresets()
                            debug(.default, "✅ EXPORT: Successfully fetched override presets on attempt \(retryCount + 1)")
                            break // Success, exit retry loop
                        } catch {
                            debug(.default, "❌ EXPORT: Attempt \(retryCount + 1) failed: \(error.localizedDescription)")
                            debug(.default, "❌ EXPORT: Full error: \(error)")
                            retryCount += 1
                            if retryCount < 3 {
                                // Wait progressively longer between retries
                                debug(.default, "🔄 EXPORT: Waiting \(retryCount * 200)ms before retry...")
                                do {
                                    try await Task.sleep(nanoseconds: UInt64(retryCount * 200_000_000)) // 0.2s, 0.4s
                                } catch {
                                    debug(.default, "⚠️ EXPORT: Sleep interrupted: \(error)")
                                    // Sleep interrupted, continue
                                }
                            }
                        }
                    }

                    debug(.default, "🔄 EXPORT: Found \(overridePresetIDs.count) override preset IDs")
                    if !overridePresetIDs.isEmpty {
                        let overrideSubcategory = String(localized: "Override Presets")
                        // Convert NSManagedObjectIDs to actual OverrideStored objects and extract their data within the Core Data context
                        // Add a small delay to ensure Core Data is ready, especially on first app launch
                        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 second

                        let viewContext = CoreDataStack.shared.persistentContainer.viewContext
                        let presetData = await viewContext.perform {
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
                            // Override: \(preset.name)

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
            }

            // Meal Presets
            if categoriesToExport.contains(.mealPresets) {
                let presetsCategory = String(localized: "Meal Presets")

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
                        let mealSubcategory = String(localized: "Meal Presets")
                        for mealPreset in mealPresetData {
                            if let carbs = mealPreset.carbs, carbs > 0 {
                                addSetting(
                                    category: presetsCategory,
                                    subcategory: mealSubcategory,
                                    name: "\(mealPreset.dish) Carbs",
                                    value: String(describing: carbs),
                                    unit: "g"
                                )
                            }

                            if let fat = mealPreset.fat, fat > 0 {
                                addSetting(
                                    category: presetsCategory,
                                    subcategory: mealSubcategory,
                                    name: "\(mealPreset.dish) Fat",
                                    value: String(describing: fat),
                                    unit: "g"
                                )
                            }

                            if let protein = mealPreset.protein, protein > 0 {
                                addSetting(
                                    category: presetsCategory,
                                    subcategory: mealSubcategory,
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

            // Convert data to the selected format and write to file
            do {
                let content: String

                switch exportFormat {
                case .csv:
                    // Helper function to escape CSV values
                    func csvEscape(_ value: String) -> String {
                        if value.contains(",") || value.contains("\"") || value.contains("\n") {
                            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
                        }
                        return value
                    }

                    var csvContent = "Setting Category,Subcategory,Setting Name,Value,Unit\n"
                    var lastPresetName: String?

                    for setting in exportSettings {
                        // Check if this is a preset category and if we're starting a new preset
                        if setting.category.contains("Presets") {
                            // Extract the base preset name (without suffixes like " Duration", " Target", etc.)
                            let settingName = setting.name
                            let basePresetName: String

                            if settingName.contains(" Duration") {
                                basePresetName = String(settingName.prefix(while: { $0 != " " }))
                            } else if settingName.contains(" Target") {
                                basePresetName = String(settingName.prefix(while: { $0 != " " }))
                            } else if settingName.contains(" Reason") {
                                basePresetName = String(settingName.prefix(while: { $0 != " " }))
                            } else if settingName.contains(" Entered By") {
                                basePresetName = String(settingName.prefix(while: { $0 != " " }))
                            } else if settingName.contains(" Carbs") {
                                basePresetName = String(settingName.prefix(while: { $0 != " " }))
                            } else if settingName.contains(" Fat") {
                                basePresetName = String(settingName.prefix(while: { $0 != " " }))
                            } else if settingName.contains(" Protein") {
                                basePresetName = String(settingName.prefix(while: { $0 != " " }))
                            } else if settingName.contains(" Advanced Settings") {
                                basePresetName = String(settingName.prefix(while: { $0 != " " }))
                            } else if settingName.contains(" SMB") {
                                basePresetName = String(settingName.prefix(while: { $0 != " " }))
                            } else if settingName.contains(" UAM") {
                                basePresetName = String(settingName.prefix(while: { $0 != " " }))
                            } else if settingName.contains(" Affects") {
                                basePresetName = String(settingName.prefix(while: { $0 != " " }))
                            } else if settingName.contains(" Target Bottom") {
                                basePresetName = String(settingName.prefix(while: { $0 != " " }))
                            } else if settingName.contains(" Half Basal Target") {
                                basePresetName = String(settingName.prefix(while: { $0 != " " }))
                            } else {
                                basePresetName = settingName
                            }

                            lastPresetName = basePresetName
                        }

                        csvContent +=
                            "\(csvEscape(setting.category)),\(csvEscape(setting.subcategory)),\(csvEscape(setting.name)),\(csvEscape(setting.value)),\(csvEscape(setting.unit))\n"
                    }
                    content = csvContent

                case .json:
                    // Convert to JSON structure
                    var jsonData: [String: Any] = [:]
                    var categorizedData: [String: Any] = [:]

                    for setting in exportSettings {
                        if categorizedData[setting.category] == nil {
                            categorizedData[setting.category] = [String: Any]()
                        }

                        var categoryData = categorizedData[setting.category] as! [String: Any]

                        if !setting.subcategory.isEmpty {
                            if categoryData[setting.subcategory] == nil {
                                categoryData[setting.subcategory] = [String: Any]()
                            }
                            var subcategoryData = categoryData[setting.subcategory] as! [String: Any]
                            subcategoryData[setting.name] = setting.unit.isEmpty ? setting
                                .value : ["value": setting.value, "unit": setting.unit]
                            categoryData[setting.subcategory] = subcategoryData
                        } else {
                            categoryData[setting.name] = setting.unit.isEmpty ? setting
                                .value : ["value": setting.value, "unit": setting.unit]
                        }

                        categorizedData[setting.category] = categoryData
                    }

                    jsonData["exportFormat"] = exportFormat.rawValue
                    jsonData["exportDate"] = ISO8601DateFormatter().string(from: Date())
                    jsonData["settings"] = categorizedData

                    let jsonDataEncoded = try JSONSerialization.data(withJSONObject: jsonData, options: .prettyPrinted)
                    content = String(data: jsonDataEncoded, encoding: .utf8) ?? "{}"
                }

                debug(
                    .default,
                    "📝 EXPORT: Writing \(exportFormat.rawValue) content (\(content.count) characters) to file: \(fileURL.path)"
                )
                debug(.default, "📝 EXPORT: Temporary directory: \(FileManager.default.temporaryDirectory.path)")
                debug(.default, "📝 EXPORT: File URL: \(fileURL)")

                try content.write(to: fileURL, atomically: true, encoding: .utf8)
                debug(.default, "✅ EXPORT: Content written to file successfully")

                // Set file attributes for better sharing compatibility
                try fileManager.setAttributes([
                    .posixPermissions: 0o644,
                    .extensionHidden: false
                ], ofItemAtPath: fileURL.path)
                debug(.default, "✅ EXPORT: File attributes set successfully")

                // Verify file was written successfully
                let fileExists = fileManager.fileExists(atPath: fileURL.path)
                let fileSize = try? fileManager.attributesOfItem(atPath: fileURL.path)[.size] as? Int ?? 0
                debug(.default, "📊 EXPORT: File verification - Exists: \(fileExists), Size: \(fileSize ?? 0) bytes")

                if !fileExists {
                    debug(.default, "❌ EXPORT: CRITICAL - File does not exist after writing!")
                    return .failure(.unknown("File was not created successfully"))
                }

                if (fileSize ?? 0) == 0 {
                    debug(.default, "❌ EXPORT: CRITICAL - File exists but has 0 bytes!")
                    return .failure(.unknown("File was created but is empty"))
                }

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

        /// Exports settings using the currently selected categories and format
        func exportSelectedSettings() async -> Result<URL, ExportError> {
            await exportSettings(categories: selectedCategories, format: selectedFormat)
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
