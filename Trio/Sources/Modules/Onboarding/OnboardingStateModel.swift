import Combine
import DanaKit
import Foundation
import LoopKit
import MedtrumKit
import MinimedKit
import Observation
import OmnipodKit
import SwiftUI

/// Model that holds the data collected during onboarding.
extension Onboarding {
    @Observable final class StateModel: BaseStateModel<Provider> {
        @ObservationIgnored @Injected() var fileStorage: FileStorage!
        @ObservationIgnored @Injected() var deviceManager: DeviceDataManager!
        @ObservationIgnored @Injected() var broadcaster: Broadcaster!
        @ObservationIgnored @Injected() var keychain: Keychain!
        @ObservationIgnored @Injected() var nightscoutManager: NightscoutManager!
        @ObservationIgnored @Injected() var notificationsManager: UserNotificationsManager!
        @ObservationIgnored @Injected() var bluetoothManager: BluetoothStateManager!
        @ObservationIgnored @Injected() var apsManager: APSManager!

        private let settingsProvider = PickerSettingsProvider.shared

        // MARK: - Determine Initial Build State

        /// Determines whether the app is in a fresh install state for Trio (new vs. returning/updating user).
        ///
        /// This check is based on the assumption that a truly clean install will only contain
        /// the `logs/` directory and the `preferences.json` file in the app's Documents directory.
        ///
        /// If this condition is met, the onboarding flow skips the `.returningUser` step and treats
        /// the user as new. If more files or directories are found, it is assumed the user is returning.
        ///
        /// Note: This check is not directly connected to a completed migration. However, if a migration
        /// has been triggered (whether successful or not), additional files such as treatment JSONs
        /// will exist, which naturally causes this check to return `false`.
        var isFreshTrioInstall: Bool {
            let fileManager = FileManager.default
            guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
                return false
            }

            let expectedLogsFolder = "logs"
            let expectedPreferencesFile = OpenAPS.Settings.preferences

            do {
                let contents = try fileManager.contentsOfDirectory(atPath: documentsURL.path)

                // Expect exactly 2 entries: "logs" and the preferences file
                guard contents.count == 2 else {
                    debug(.default, "Trio install is not fresh; returning user.")
                    return false
                }

                // Ensure they match exactly
                let expectedSet = Set([expectedLogsFolder, expectedPreferencesFile])
                let actualSet = Set(contents)

                let isFreshInstall = expectedSet == actualSet
                debug(.default, "Trio install is fresh; new user.")

                return isFreshInstall

            } catch {
                debug(.default, "Cannot determine Initial Build State. Failed to read documents directory: \(error)")
                return false
            }
        }

        // MARK: - Nightscout Setup

        var nightscoutSetupOption: NightscoutSetupOption = .noSelection
        var nightscoutImportOption: NightscoutImportOption = .noSelection
        var nightscoutUrl = ""
        var nightscoutSecret = ""
        var nightscoutResponseMessage = ""
        var isValidNightscoutURL: Bool = false
        var isConnectingToNS: Bool = false
        var isConnectedToNS: Bool = false
        var nightscoutImportError: NightscoutImportError?
        var nightscoutImportStatus: ImportStatus = .none
        var isUploadEnabled: Bool = true
        var uploadGlucose: Bool = true

        // MARK: - Units and Pump Omboarding Option

        var units: GlucoseUnits = .mgdL
        private var selectedPumpOption: PumpCatalogEntry?
        var pumpOptionForOnboardingUnits: PumpCatalogEntry {
            get {
                // let user edit selection and return user-selection, if present
                if let selected = selectedPumpOption {
                    return selected
                }

                // Users upgrading from a pre-onboarding Trio already have a pump manager, so preselect it.
                // Matching on pluginIdentifier also picks up the legacy Omnipod identifiers, which the old
                // downcast cascade could not.
                let defaultOption = apsManager?.pumpManager
                    .map { DeviceCatalog.onboardingPump(forPersistedIdentifier: $0.pluginIdentifier) }
                    ?? DeviceCatalog.defaultOnboardingPump

                // cache it so picker can stay in sync
                selectedPumpOption = defaultOption

                return defaultOption
            }
            set {
                selectedPumpOption = newValue
            }
        }

        // MARK: - Time Values (shared)

        let sharedTimeValues = stride(from: 0.0, to: 1.days.timeInterval, by: 30.minutes.timeInterval).map { $0 }.sorted()

        // MARK: - Carb Ratio

        let carbRatioPickerSetting = PickerSetting(value: 30, step: 0.1, min: 1, max: 50, type: .gram)
        var carbRatioItems: [TherapySettingsEditor.Item] = []
        var initialCarbRatioItems: [TherapySettingsEditor.Item] = []
        var carbRatioTimeValues: [TimeInterval] { sharedTimeValues }
        var carbRatioRateValues: [Decimal] { settingsProvider.generatePickerValues(from: carbRatioPickerSetting, units: units) }

        // MARK: - Basal Profile

        var basalRatePickerSetting: PickerSetting {
            // Deliberately reads the stored value, not the getter: before the user picks anything this stays nil
            // and falls back to the default pump's bounds, which is the pre-catalog behaviour.
            let capability = (selectedPumpOption ?? DeviceCatalog.defaultOnboardingPump).basalCapability
            return PickerSetting(
                value: 0.1,
                step: capability.step,
                min: capability.minimum,
                max: capability.maximum,
                type: .insulinUnitPerHour
            )
        }

        var basalProfileItems: [TherapySettingsEditor.Item] = []
        var initialBasalProfileItems: [TherapySettingsEditor.Item] = []
        var basalProfileTimeValues: [TimeInterval] { sharedTimeValues }
        var basalProfileRateValues: [Decimal] { settingsProvider.generatePickerValues(from: basalRatePickerSetting, units: units)
        }

        // MARK: - Insulin Sensitivity Factor (ISF)

        var sensitivityPickerSetting = PickerSetting(value: 200, step: 1, min: 9, max: 540, type: .glucose)
        var isfItems: [TherapySettingsEditor.Item] = []
        var initialISFItems: [TherapySettingsEditor.Item] = []
        var isfTimeValues: [TimeInterval] { sharedTimeValues }
        var isfRateValues: [Decimal] { settingsProvider.generatePickerValues(from: sensitivityPickerSetting, units: units) }

        // MARK: - Glucose Targets

        let letTargetPickerSetting = PickerSetting(value: 110, step: 1, min: 72, max: 180, type: .glucose)
        var targetItems: [TherapySettingsEditor.Item] = []
        var initialTargetItems: [TherapySettingsEditor.Item] = []
        var targetTimeValues: [TimeInterval] { sharedTimeValues }
        var targetRateValues: [Decimal] { settingsProvider.generatePickerValues(from: letTargetPickerSetting, units: units) }

        // MARK: - Delivery Limit Defaults

        var maxBolus: Decimal = 10
        var maxBasal: Decimal = 2
        var maxIOB: Decimal = 0
        var maxCOB: Decimal = 120
        var minimumSafetyThreshold: Decimal = 60

        // MARK: - Algorithm Settings Defaults

        // Autosens Settings
        var autosensMin: Decimal = 0.7
        var autosensMax: Decimal = 1.2
        var rewindResetsAutosens: Bool = true

        var filteredAutosensSettingsSubsteps: [AutosensSettingsSubstep] {
            if pumpOptionForOnboardingUnits.reportsRewindEvents {
                return AutosensSettingsSubstep.allCases
            } else {
                return [AutosensSettingsSubstep.autosensMin, AutosensSettingsSubstep.autosensMax]
            }
        }

        // SMB Settings
        var enableSMBAlways: Bool = false
        var enableSMBWithCOB: Bool = false
        var enableSMBWithTempTarget: Bool = false
        var enableSMBAfterCarbs: Bool = false
        var enableSMBWithHighGlucoseTarget: Bool = false
        var highGlucoseTarget: Decimal = 110
        var allowSMBWithHighTempTarget: Bool = false
        var enableUAM: Bool = false
        var maxSMBMinutes: Decimal = 30
        var maxUAMMinutes: Decimal = 30
        var maxDeltaGlucoseThreshold: Decimal = 0.2

        // Target Behavior
        var highTempTargetRaisesSensitivity: Bool = false
        var lowTempTargetLowersSensitivity: Bool = false
        var sensitivityRaisesTarget: Bool = false
        var resistanceLowersTarget: Bool = false
        var halfBasalTarget: Decimal = 160

        // MARK: - Permission Requests

        var hasNotificationsGranted = false
        var shouldDisplayCustomNotificationAlert: Bool = false

        var shouldDisplayBluetoothRequestAlert: Bool = false
        var hasBluetoothGranted = false

        // MARK: - Subscribe

        override func subscribe() {
            // Keychain items are not removed, even after uninstalling the app. Attempt to read them initially.
            nightscoutUrl = keychain.getValue(String.self, forKey: NightscoutConfig.Config.urlKey) ?? ""
            nightscoutSecret = keychain.getValue(String.self, forKey: NightscoutConfig.Config.secretKey) ?? ""
            isConnectedToNS = false
            isConnectingToNS = false
            isValidNightscoutURL = false

            if !isFreshTrioInstall {
                // Attempt to fetch existing units, therapy settings and delivery limits from file
                units = settingsManager.settings.units
                fetchExistingTherapySettingsFromFile()
                fetchExistingDeliveryLimtisFromFile()
            }
        }

        // MARK: - Helpers

        /// Finds the index of the closest `Decimal` value in the given array.
        /// - Parameters:
        ///   - value: The value to match.
        ///   - array: The array to search in.
        /// - Returns: Closest index in array.
        func closestValue(for value: Decimal, in array: [Decimal]) -> Decimal {
            array.enumerated().min(by: {
                abs($0.element - value) < abs($1.element - value)
            })?.element ?? array[0]
        }

        /// Finds the index of the closest `TimeInterval` value in the given array.
        /// - Parameters:
        ///   - value: The time value to match.
        ///   - array: The array to search in.
        /// - Returns: Closest index in array.
        func closestValue(for value: TimeInterval, in array: [TimeInterval]) -> TimeInterval {
            array.enumerated().min(by: {
                abs($0.element - value) < abs($1.element - value)
            })?.element ?? array[0]
        }

        /// A date formatter for time strings used in saved settings.
        private var timeFormatter: DateFormatter {
            let formatter = DateFormatter()
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "HH:mm:ss"
            return formatter
        }

        /// Remaps therapy items affected by a glucose unit change (mg/dL vs mmol/L).
        ///
        /// This function updates glucose target and insulin sensitivity (ISF) items to use the closest valid index
        /// from the newly available rate arrays, preserving the original value intent.
        ///
        /// Call this after the user changes the unit selection.
        ///
        /// See also: `UnitSelectionStepView` `.onChange()` handlers.
        func remapTherapyItemsForChangedUnits() {
            // Targets
            targetItems = remapTherapyItems(
                items: targetItems,
                timeValues: targetTimeValues,
                rateValues: targetRateValues
            )

            // ISF
            isfItems = remapTherapyItems(
                items: isfItems,
                timeValues: isfTimeValues,
                rateValues: isfRateValues
            )
        }

        /// Remaps therapy items affected by a pump model change.
        ///
        /// Updates basal profile items to use the closest valid index from
        /// the updated basal rate and time arrays, preserving the user's settings
        /// as closely as possible when switching between pump models.
        ///
        /// Call this after the user selects a new pump model.
        ///
        /// See also: `UnitSelectionStepView` `.onChange()` handlers.
        func remapTherapyItemsForChangedPumpModel() {
            basalProfileItems = remapTherapyItems(
                items: basalProfileItems,
                timeValues: basalProfileTimeValues,
                rateValues: basalProfileRateValues
            )
        }

        func remapTherapyItems(
            items: [TherapySettingsEditor.Item],
            timeValues: [TimeInterval],
            rateValues: [Decimal]
        ) -> [TherapySettingsEditor.Item] {
            items.map { item in
                let newTime = closestValue(for: item.time, in: timeValues)
                let newValue = closestValue(for: item.value, in: rateValues)
                return TherapySettingsEditor.Item(time: newTime, value: newValue)
            }
        }

        // MARK: - Fetch existing therapy settings from file

        /// Loads existing therapy settings from the provider and maps them into UI editor items.
        ///
        /// This function processes therapy-related configurations (glucose targets, basal rates,
        /// carb ratios, and insulin sensitivity factors) stored in file-backed models from the provider.
        /// It calculates the closest matching indices for time and rate values to map them to corresponding
        /// `Editor.Item` models for use in the UI.
        ///
        /// - Populates:
        ///   - `targetItems` and `initialTargetItems` with glucose target entries.
        ///   - `basalProfileItems` and `initialBasalProfileItems` with basal rate entries.
        ///   - `carbRatioItems` and `initialCarbRatioItems` with carbohydrate ratio entries.
        ///   - `isfItems` and `initialISFItems` with insulin sensitivity factor entries.
        func fetchExistingTherapySettingsFromFile() {
            targetItems = provider.glucoseTargetsOnFile.targets.map { value in
                let time = closestValue(for: TimeInterval(Double(value.offset * 60)), in: targetTimeValues)
                let value = closestValue(for: value.low, in: targetRateValues)
                return TherapySettingsEditor.Item(time: time, value: value)
            }
            initialTargetItems = targetItems.map { TherapySettingsEditor.Item(copying: $0) }

            basalProfileItems = provider.basalProfileOnFile.map { value in
                let time = closestValue(for: TimeInterval(Double(value.minutes * 60)), in: basalProfileTimeValues)
                let value = closestValue(for: value.rate, in: basalProfileRateValues)
                return TherapySettingsEditor.Item(time: time, value: value)
            }
            initialBasalProfileItems = basalProfileItems.map { TherapySettingsEditor.Item(copying: $0) }

            carbRatioItems = provider.carbRatiosOnFile.schedule.map { value in
                let time = closestValue(for: TimeInterval(Double(value.offset * 60)), in: carbRatioTimeValues)
                let value = closestValue(for: value.ratio, in: carbRatioRateValues)
                return TherapySettingsEditor.Item(time: time, value: value)
            }
            initialCarbRatioItems = carbRatioItems.map { TherapySettingsEditor.Item(copying: $0) }

            isfItems = provider.isfOnFile.sensitivities.map { value in
                let time = closestValue(for: TimeInterval(Double(value.offset * 60)), in: isfTimeValues)
                let value = closestValue(for: value.sensitivity, in: isfRateValues)

                return TherapySettingsEditor.Item(time: time, value: value)
            }
            initialISFItems = isfItems.map { TherapySettingsEditor.Item(copying: $0) }
        }

        /// Total insulin a basal schedule delivers over 24 hours.
        /// - Parameter segments: `(start minute of day, rate in U/hr)`, in any order.
        static func totalDailyBasal(segments: [(startMinutes: Int, rate: Decimal)]) -> Decimal {
            let sorted = segments.sorted { $0.startMinutes < $1.startMinutes }
            guard !sorted.isEmpty else { return 0 }

            return sorted.enumerated().reduce(Decimal(0)) { total, element in
                let (index, segment) = element
                let end = index + 1 < sorted.count ? sorted[index + 1].startMinutes : 24 * 60
                let minutes = end - segment.startMinutes
                guard minutes > 0 else { return total }
                return total + segment.rate * Decimal(minutes) / 60
            }
        }

        /// Starting Max IOB for a new user: a third of their total daily basal, snapped to the picker's step.
        static func suggestedMaxIOB(totalDailyBasal: Decimal, setting: PickerSetting) -> Decimal {
            let suggestion = totalDailyBasal / 3
            guard setting.step > 0 else { return suggestion.clamp(to: setting) }
            let steps = rounded(suggestion / setting.step, scale: 0, roundingMode: .plain)
            return (steps * setting.step).clamp(to: setting)
        }

        /// Seeds Max IOB from the entered basal schedule when the user first reaches delivery limits.
        /// Runs there, not in `subscribe()`: a fresh install has no basal profile yet at that point.
        func seedMaxIOBIfUnset() {
            guard maxIOB <= 0 else { return }
            maxIOB = Self.suggestedMaxIOB(
                totalDailyBasal: totalDailyBasal(),
                setting: settingsProvider.settings.maxIOB
            )
        }

        /// Total insulin the entered basal profile delivers over 24 hours.
        func totalDailyBasal() -> Decimal {
            let segments = basalProfileItems.compactMap { item -> (startMinutes: Int, rate: Decimal)? in
                (Int(item.time / 60), item.value)
            }
            return Self.totalDailyBasal(segments: segments)
        }

        /// Loads delivery limit settings (Units, Max IOB, Max COB, Max Bolus, Max Basal) from the provider.
        ///
        /// Retrieves pump-related safety and delivery limits from both the provider's
        /// file-backed pump settings and app-specific preferences. These values are used
        /// to pre-fill the delivery limits editor in the onboarding or settings UI.
        ///
        /// - Populates:
        ///   - `maxBolus` and `maxBasal` from file-based pump settings.
        ///   - `maxIOB`, `maxCOB`, and `minimumSafetyThreshold` from app preferences.
        ///   - `units` from app settings.
        func fetchExistingDeliveryLimtisFromFile() {
            let pumpSettingsFromFile = provider.pumpSettingsFromFile
            let providedSettings = settingsProvider.settings

            if let pumpSettingsFromFile = pumpSettingsFromFile {
                maxBolus = pumpSettingsFromFile.maxBolus.clamp(to: providedSettings.maxBolus)
                maxBasal = pumpSettingsFromFile.maxBasal.clamp(to: providedSettings.maxBasal)
            }

            let preferences = settingsManager.preferences
            maxIOB = preferences.maxIOB.clamp(to: providedSettings.maxIOB)
            maxCOB = preferences.maxCOB.clamp(to: providedSettings.maxCOB)
            minimumSafetyThreshold = preferences.threshold_setting
        }

        // MARK: - Add Initials

        /// Adds a default ISF editor item at 00:00 with a standard sensitivity value.
        func addInitialISF() {
            addInitialItem(
                defaultValue: 200,
                rateValues: isfRateValues,
                assign: { isfItems = $0 }
            )
        }

        /// Adds a default basal rate editor item at 00:00 with a typical rate value.
        func addInitialBasalRate() {
            addInitialItem(
                defaultValue: 0.1,
                rateValues: basalProfileRateValues,
                assign: { basalProfileItems = $0 }
            )
        }

        /// Adds a default carb ratio editor item at 00:00 with a standard ratio.
        func addInitialCarbRatio() {
            addInitialItem(
                defaultValue: 30,
                rateValues: carbRatioRateValues,
                assign: { carbRatioItems = $0 }
            )
        }

        /// Adds a default glucose target item at 00:00 with a typical target value.
        func addInitialTarget() {
            addInitialItem(
                defaultValue: 110,
                rateValues: targetRateValues,
                assign: { targetItems = $0 },
            )
        }

        /// Adds an initial therapy setting item for a given editor item type.
        /// - Parameters:
        ///   - defaultValue: The expected default value to use.
        ///   - rateValues: The array of rate values for the item.
        ///   - assign: A closure that assigns the newly created array to the correct property.
        private func addInitialItem(
            defaultValue: Decimal,
            rateValues: [Decimal],
            assign: ([TherapySettingsEditor.Item]) -> Void
        ) {
            let time: TimeInterval = 0
            let value = closestValue(for: defaultValue, in: rateValues)
            assign([TherapySettingsEditor.Item(time: time, value: value)])
        }

        // MARK: - Validate

        /// Removes duplicate entries from `carbRatioItems`, ensures sorting by time index,
        /// and forces the first entry to start at 00:00 (timeIndex 0).
        func validateCarbRatios() {
            carbRatioItems = validated(items: carbRatioItems)
        }

        /// Removes duplicate entries from `basalProfileItems`, ensures sorting by time index,
        /// and forces the first entry to start at 00:00 (timeIndex 0).
        func validateBasal() {
            basalProfileItems = validated(items: basalProfileItems)
        }

        /// Removes duplicate entries from `isfItems`, ensures sorting by time index,
        /// and forces the first entry to start at 00:00 (timeIndex 0).
        func validateISF() {
            isfItems = validated(items: isfItems)
        }

        /// Removes duplicate entries from `targetItems`, ensures sorting by time index,
        /// and forces the first entry to start at 00:00 (timeIndex 0).
        func validateTarget() {
            targetItems = validated(items: targetItems)
        }

        /// Removes duplicates, sorts by time, and ensures the first entry starts at 00:00.
        /// - Parameters:
        ///   - items: The list of items to validate.
        ///   - timeIndexKeyPath: A writable key path to the timeIndex property.
        /// - Returns: A validated and sorted list of items with the first entry at 00:00.
        private func validated(items: [TherapySettingsEditor.Item]) -> [TherapySettingsEditor.Item] {
            var result = Array(Set(items)).sorted { $0.time < $1.time }
            if !result.isEmpty, result[0].time != 0 {
                result[0].time = 0
            }
            return result
        }

        // MARK: - Save

        /// Saves the carb ratio items to file storage and sets them as initial values.
        func saveCarbRatios() {
            let schedule = carbRatioItems.map { $0.asCarbRatioEntry() }
            fileStorage.save(CarbRatios(units: .grams, schedule: schedule), as: OpenAPS.Settings.carbRatios)
            initialCarbRatioItems = carbRatioItems
        }

        /// Saves the basal profile items to file storage and sets them as initial values.
        func saveBasalProfile() {
            let profile = basalProfileItems.map { $0.asBasalProfileEntry() }
            fileStorage.save(profile, as: OpenAPS.Settings.basalProfile)
            initialBasalProfileItems = basalProfileItems
        }

        /// Saves the insulin sensitivity (ISF) items to file storage and sets them as initial values.
        func saveISFValues() {
            let sensitivities = isfItems.map { $0.asInsulinSensitivityEntry() }
            let profile = InsulinSensitivities(units: .mgdL, userPreferredUnits: .mgdL, sensitivities: sensitivities)
            fileStorage.save(profile, as: OpenAPS.Settings.insulinSensitivities)
            initialISFItems = isfItems
        }

        /// Saves the glucose target items to file storage and sets them as initial values.
        func saveTargets() {
            let targets = targetItems.map { $0.asBGTargetEntry() }
            let profile = BGTargets(units: .mgdL, userPreferredUnits: .mgdL, targets: targets)
            fileStorage.save(profile, as: OpenAPS.Settings.bgTargets)
            initialTargetItems = targetItems
        }

        /// Persists all onboarding data by applying settings and saving therapy values.
        func saveOnboardingData() {
            applyToSettings()
            applyToPreferences()
            applyToPumpSettings()
            saveTargets()
            saveBasalProfile()
            saveCarbRatios()
            saveISFValues()
        }

        /// Applies the selected glucose units to the app's settings.
        func applyToSettings() {
            var settingsCopy = settingsManager.settings
            settingsCopy.units = units

            if nightscoutSetupOption == .setupNightscout {
                settingsCopy.isUploadEnabled = isUploadEnabled
                settingsCopy.uploadGlucose = uploadGlucose
            }

            // ensure existing values cannot exceed new guardrails
            if !isFreshTrioInstall {
                let providedSettings = settingsProvider.settings

                settingsCopy.carbsRequiredThreshold = settingsCopy.carbsRequiredThreshold
                    .clamp(to: providedSettings.carbsRequiredThreshold)
                settingsCopy.individualAdjustmentFactor = settingsCopy.individualAdjustmentFactor
                    .clamp(to: providedSettings.individualAdjustmentFactor)
                settingsCopy.minuteInterval = settingsCopy.minuteInterval.clamp(to: providedSettings.minuteInterval)
                settingsCopy.delay = settingsCopy.delay.clamp(to: providedSettings.delay)
                settingsCopy.high = settingsCopy.high.clamp(to: providedSettings.high)
                settingsCopy.low = settingsCopy.low.clamp(to: providedSettings.low)
                settingsCopy.maxCarbs = settingsCopy.maxCarbs.clamp(to: providedSettings.maxCarbs)
                settingsCopy.maxFat = settingsCopy.maxFat.clamp(to: providedSettings.maxFat)
                settingsCopy.maxProtein = settingsCopy.maxProtein.clamp(to: providedSettings.maxProtein)
                settingsCopy.overrideFactor = settingsCopy.overrideFactor.clamp(to: providedSettings.overrideFactor)
                settingsCopy.fattyMealFactor = settingsCopy.fattyMealFactor.clamp(to: providedSettings.fattyMealFactor)
                settingsCopy.sweetMealFactor = settingsCopy.sweetMealFactor.clamp(to: providedSettings.sweetMealFactor)
            }

            settingsManager.settings = settingsCopy
        }

        /// Applies the selected delivery preferences to the app's settings.
        func applyToPreferences() {
            var preferences = Preferences()

            // delivery limits (those that are preference-bound, not pump-settings-bound
            preferences.maxIOB = maxIOB
            preferences.maxCOB = maxCOB
            preferences.threshold_setting = minimumSafetyThreshold

            // autosens
            preferences.autosensMin = autosensMin
            preferences.autosensMax = autosensMax
            preferences.rewindResetsAutosens = rewindResetsAutosens

            // smb settings
            preferences.enableSMBAlways = enableSMBAlways
            preferences.enableSMBWithCOB = enableSMBWithCOB
            preferences.enableSMBWithTemptarget = enableSMBWithTempTarget
            preferences.enableSMBAfterCarbs = enableSMBAfterCarbs
            preferences.enableSMB_high_bg = enableSMBWithHighGlucoseTarget
            preferences.enableSMB_high_bg_target = highGlucoseTarget
            preferences.allowSMBWithHighTemptarget = allowSMBWithHighTempTarget
            preferences.enableUAM = enableUAM
            preferences.maxSMBBasalMinutes = maxSMBMinutes
            preferences.maxUAMSMBBasalMinutes = maxUAMMinutes
            preferences.maxDeltaBGthreshold = maxDeltaGlucoseThreshold

            // target behavior
            preferences.highTemptargetRaisesSensitivity = highTempTargetRaisesSensitivity
            preferences.lowTemptargetLowersSensitivity = lowTempTargetLowersSensitivity
            preferences.sensitivityRaisesTarget = sensitivityRaisesTarget
            preferences.resistanceLowersTarget = resistanceLowersTarget
            preferences.halfBasalExerciseTarget = halfBasalTarget

            // default suspendZeroesIOB to true
            if !preferences.suspendZerosIOB {
                preferences.suspendZerosIOB = true
            }

            // ensure correct bolusIncrement is set, if user is onboarding with paired pump
            if let pumpManager = apsManager?.pumpManager {
                let bolusIncrement = Decimal(
                    pumpManager.supportedBolusVolumes.first ??
                        Double(
                            settingsManager.preferences
                                .bolusIncrement
                        )
                )
                preferences.bolusIncrement = bolusIncrement > 0 ? bolusIncrement : 0.1
            }

            settingsManager.preferences = preferences
        }

        /// Saves pump delivery limits to persistent storage and broadcasts changes.
        func applyToPumpSettings() {
            let defaultDIA = settingsProvider.settings.dia.value
            let pumpSettings = PumpSettings(insulinActionCurve: defaultDIA, maxBolus: maxBolus, maxBasal: maxBasal)
            fileStorage.save(pumpSettings, as: OpenAPS.Settings.settings)
        }
    }
}
