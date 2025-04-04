import Combine
import Foundation
import LoopKit
import Observation
import SwiftUI

/// Model that holds the data collected during onboarding.
extension Onboarding {
    @Observable final class StateModel: BaseStateModel<Provider> {
        @ObservationIgnored @Injected() var fileStorage: FileStorage!
        @ObservationIgnored @Injected() var deviceManager: DeviceDataManager!
        @ObservationIgnored @Injected() var broadcaster: Broadcaster!
        @ObservationIgnored @Injected() var keychain: Keychain!
        @ObservationIgnored @Injected() var nightscoutManager: NightscoutManager!

        private let settingsProvider = PickerSettingsProvider.shared

        // MARK: - App Diagnostics

        var diagnostisSharingOption: DiagnostisSharingOption = .enabled

        // MARK: - Nightscout Setup

        var nightscoutSetupOption: NightscoutSetupOption = .noSelection
        var nightscoutImportOption: NightscoutImportOption = .noSelection
        var url = ""
        var secret = ""
        var message = ""
        var isValidURL: Bool = false
        var connecting: Bool = false
        var isConnectedToNS: Bool = false
        var nightscoutImportErrors: [String] = []
        var nightscoutImportStatus: ImportStatus = .finished

        // MARK: - Units and Pump Model

        var units: GlucoseUnits = .mgdL
        var pumpModel: PumpOptionsForOnboardingUnits = .omnipodDash

        // MARK: - Time Values (shared)

        let sharedTimeValues = stride(from: 0.0, to: 1.days.timeInterval, by: 30.minutes.timeInterval).map { $0 }.sorted()

        // MARK: - Carb Ratio

        let carbRatioPickerSetting = PickerSetting(value: 3, step: 0.1, min: 3, max: 50, type: .gram)
        var carbRatioItems: [CarbRatioEditor.Item] = []
        var initialCarbRatioItems: [CarbRatioEditor.Item] = []
        var carbRatioTimeValues: [TimeInterval] { sharedTimeValues }
        var carbRatioRateValues: [Decimal] { settingsProvider.generatePickerValues(from: carbRatioPickerSetting, units: units) }

        // MARK: - Basal Profile

        var basalRatePickerSetting: PickerSetting {
            switch pumpModel {
            case .dana,
                 .minimed:
                return PickerSetting(value: 0.1, step: 0.1, min: 0.1, max: 30, type: .insulinUnit)
            case .omnipodDash,
                 .omnipodEros:
                return PickerSetting(value: 0.5, step: 0.05, min: 0.05, max: 30, type: .insulinUnit)
            }
        }

        var basalProfileItems: [BasalProfileEditor.Item] = []
        var initialBasalProfileItems: [BasalProfileEditor.Item] = []
        var basalProfileTimeValues: [TimeInterval] { sharedTimeValues }
        var basalProfileRateValues: [Decimal] { settingsProvider.generatePickerValues(from: basalRatePickerSetting, units: units)
        }

        // MARK: - Insulin Sensitivity Factor (ISF)

        var sensitivityPickerSetting = PickerSetting(value: 100, step: 1, min: 9, max: 540, type: .glucose)
        var isfItems: [ISFEditor.Item] = []
        var initialISFItems: [ISFEditor.Item] = []
        var isfTimeValues: [TimeInterval] { sharedTimeValues }
        var isfRateValues: [Decimal] { settingsProvider.generatePickerValues(from: sensitivityPickerSetting, units: units) }

        // MARK: - Glucose Targets

        let letTargetPickerSetting = PickerSetting(value: 100, step: 1, min: 72, max: 180, type: .glucose)
        var targetItems: [TargetsEditor.Item] = []
        var initialTargetItems: [TargetsEditor.Item] = []
        var targetTimeValues: [TimeInterval] { sharedTimeValues }
        var targetRateValues: [Decimal] { settingsProvider.generatePickerValues(from: letTargetPickerSetting, units: units) }

        // MARK: - Delivery Limit Defaults

        var maxBolus: Decimal = 10
        var maxBasal: Decimal = 2
        var maxIOB: Decimal = 0
        var maxCOB: Decimal = 120

        // MARK: - Subscribe

        override func subscribe() {
            // Keychain items are not removed, even after uninstalling the app. Attempt to read them initially.
            url = keychain.getValue(String.self, forKey: NightscoutConfig.Config.urlKey) ?? ""
            secret = keychain.getValue(String.self, forKey: NightscoutConfig.Config.secretKey) ?? ""
        }

        // MARK: - Helpers

        /// Finds the index of the closest Decimal value in the given array.
        /// - Parameters:
        ///   - value: The value to match.
        ///   - array: The array to search in.
        /// - Returns: Closest index in array.
        private func closestIndex(for value: Decimal, in array: [Decimal]) -> Int {
            array.enumerated().min(by: {
                abs($0.element - value) < abs($1.element - value)
            })?.offset ?? 0
        }

        /// Finds the index of the closest TimeInterval value in the given array.
        /// - Parameters:
        ///   - value: The time value to match.
        ///   - array: The array to search in.
        /// - Returns: Closest index in array.
        private func closestIndex(for value: TimeInterval, in array: [TimeInterval]) -> Int {
            array.enumerated().min(by: {
                abs($0.element - value) < abs($1.element - value)
            })?.offset ?? 0
        }

        /// A date formatter for time strings used in saved settings.
        private var timeFormatter: DateFormatter {
            let formatter = DateFormatter()
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "HH:mm:ss"
            return formatter
        }

        // MARK: - Get Therapy Items

        /// Converts ISF editor items to a list of `TherapySettingItem`.
        /// - Returns: Sorted list of therapy setting items based on ISF.
        func getISFTherapyItems() -> [TherapySettingItem] {
            getTherapyItems(from: isfItems, rateValues: isfRateValues, timeValues: isfTimeValues)
        }

        /// Converts basal profile editor items to a list of `TherapySettingItem`.
        /// - Returns: Sorted list of therapy setting items based on basal rates.
        func getBasalTherapyItems() -> [TherapySettingItem] {
            getTherapyItems(
                from: basalProfileItems,
                rateValues: basalProfileRateValues,
                timeValues: basalProfileTimeValues
            )
        }

        /// Converts carb ratio editor items to a list of `TherapySettingItem`.
        /// - Returns: Sorted list of therapy setting items based on carb ratios.
        func getCarbRatioTherapyItems() -> [TherapySettingItem] {
            getTherapyItems(from: carbRatioItems, rateValues: carbRatioRateValues, timeValues: carbRatioTimeValues)
        }

        /// Converts glucose target editor items to a list of `TherapySettingItem`.
        /// - Returns: Sorted list of therapy setting items based on glucose targets.
        func getTargetTherapyItems() -> [TherapySettingItem] {
            targetItems.map {
                TherapySettingItem(
                    time: targetTimeValues[$0.timeIndex],
                    value: targetRateValues[$0.lowIndex]
                )
            }.sorted { $0.time < $1.time }
        }

        /// Generic helper to convert any type of editor item into therapy setting items.
        /// - Parameters:
        ///   - items: An array of items conforming to `TherapyItemConvertible`.
        ///   - rateValues: The rate values to be used.
        ///   - timeValues: The time values to be used.
        /// - Returns: A sorted array of `TherapySettingItem`.
        private func getTherapyItems<T: TherapyItemConvertible>(
            from items: [T],
            rateValues: [Decimal],
            timeValues: [TimeInterval]
        ) -> [TherapySettingItem] {
            items.map {
                TherapySettingItem(
                    time: timeValues[$0.timeIndex],
                    value: rateValues[$0.rateIndex]
                )
            }.sorted { $0.time < $1.time }
        }

        // MARK: - Unified Update Methods

        /// Updates the ISF editor items based on the provided therapy setting items.
        /// - Parameter therapyItems: The list of therapy items to update from.
        func updateISF(from therapyItems: [TherapySettingItem]) {
            isfItems = therapyItems.map {
                ISFEditor.Item(
                    rateIndex: closestIndex(for: $0.value, in: isfRateValues),
                    timeIndex: closestIndex(for: $0.time, in: isfTimeValues)
                )
            }.sorted { $0.timeIndex < $1.timeIndex }
        }

        /// Updates the basal rate editor items based on the provided therapy setting items.
        /// - Parameter therapyItems: The list of therapy items to update from.
        func updateBasal(from therapyItems: [TherapySettingItem]) {
            basalProfileItems = therapyItems.map {
                BasalProfileEditor.Item(
                    rateIndex: closestIndex(for: $0.value, in: basalProfileRateValues),
                    timeIndex: closestIndex(for: $0.time, in: basalProfileTimeValues)
                )
            }.sorted { $0.timeIndex < $1.timeIndex }
        }

        /// Updates the carb ratio editor items based on the provided therapy setting items.
        /// - Parameter therapyItems: The list of therapy items to update from.
        func updateCarbRatio(from therapyItems: [TherapySettingItem]) {
            carbRatioItems = therapyItems.map {
                CarbRatioEditor.Item(
                    rateIndex: closestIndex(for: $0.value, in: carbRatioRateValues),
                    timeIndex: closestIndex(for: $0.time, in: carbRatioTimeValues)
                )
            }.sorted { $0.timeIndex < $1.timeIndex }
        }

        /// Updates the glucose target editor items based on the provided therapy setting items.
        /// - Parameter therapyItems: The list of therapy items to update from.
        func updateTargets(from therapyItems: [TherapySettingItem]) {
            targetItems = therapyItems.map {
                let rateIndex = closestIndex(for: $0.value, in: targetRateValues)
                let timeIndex = closestIndex(for: $0.time, in: targetTimeValues)

                return TargetsEditor.Item(
                    lowIndex: rateIndex,
                    highIndex: rateIndex,
                    timeIndex: timeIndex
                )
            }.sorted { $0.timeIndex < $1.timeIndex }
        }

        // MARK: - Add Initials

        /// Adds a default ISF editor item at 00:00 with a standard sensitivity value.
        func addInitialISF() {
            addInitialItem(
                defaultValue: 50,
                rateValues: isfRateValues,
                assign: { isfItems = $0 },
                makeItem: ISFEditor.Item.init
            )
        }

        /// Adds a default basal rate editor item at 00:00 with a typical rate value.
        func addInitialBasalRate() {
            addInitialItem(
                defaultValue: 0.1,
                rateValues: basalProfileRateValues,
                assign: { basalProfileItems = $0 },
                makeItem: BasalProfileEditor.Item.init
            )
        }

        /// Adds a default carb ratio editor item at 00:00 with a standard ratio.
        func addInitialCarbRatio() {
            addInitialItem(
                defaultValue: 10,
                rateValues: carbRatioRateValues,
                assign: { carbRatioItems = $0 },
                makeItem: CarbRatioEditor.Item.init
            )
        }

        /// Adds a default glucose target item at 00:00 with a typical target value.
        func addInitialTarget() {
            let timeIndex = 0
            let rateIndex = closestIndex(for: 100, in: targetRateValues)
            targetItems = [TargetsEditor.Item(lowIndex: rateIndex, highIndex: rateIndex, timeIndex: timeIndex)]
        }

        /// Adds an initial therapy setting item for a given editor item type.
        /// - Parameters:
        ///   - defaultValue: The expected default value to use.
        ///   - rateValues: The array of rate values for the item.
        ///   - assign: A closure that assigns the newly created array to the correct property.
        private func addInitialItem<ItemType>(
            defaultValue: Decimal,
            rateValues: [Decimal],
            assign: ([ItemType]) -> Void,
            makeItem: (Int, Int) -> ItemType
        ) {
            let timeIndex = 0
            let rateIndex = closestIndex(for: defaultValue, in: rateValues)
            assign([makeItem(rateIndex, timeIndex)])
        }

        // MARK: - Validate

        /// Removes duplicate entries from `carbRatioItems`, ensures sorting by time index,
        /// and forces the first entry to start at 00:00 (timeIndex 0).
        func validateCarbRatios() {
            carbRatioItems = validated(items: carbRatioItems, timeIndexKeyPath: \.timeIndex)
        }

        /// Removes duplicate entries from `basalProfileItems`, ensures sorting by time index,
        /// and forces the first entry to start at 00:00 (timeIndex 0).
        func validateBasal() {
            basalProfileItems = validated(items: basalProfileItems, timeIndexKeyPath: \.timeIndex)
        }

        /// Removes duplicate entries from `isfItems`, ensures sorting by time index,
        /// and forces the first entry to start at 00:00 (timeIndex 0).
        func validateISF() {
            isfItems = validated(items: isfItems, timeIndexKeyPath: \.timeIndex)
        }

        /// Removes duplicate entries from `targetItems`, ensures sorting by time index,
        /// and forces the first entry to start at 00:00 (timeIndex 0).
        func validateTarget() {
            targetItems = validated(items: targetItems, timeIndexKeyPath: \.timeIndex)
        }

        /// Removes duplicates, sorts by time, and ensures the first entry starts at 00:00.
        /// - Parameters:
        ///   - items: The list of items to validate.
        ///   - timeIndexKeyPath: A writable key path to the timeIndex property.
        /// - Returns: A validated and sorted list of items with the first entry at 00:00.
        private func validated<T: Hashable>(items: [T], timeIndexKeyPath: WritableKeyPath<T, Int>) -> [T] {
            var result = Array(Set(items)).sorted { $0[keyPath: timeIndexKeyPath] < $1[keyPath: timeIndexKeyPath] }
            if !result.isEmpty, result[0][keyPath: timeIndexKeyPath] != 0 {
                result[0][keyPath: timeIndexKeyPath] = 0
            }
            return result
        }

        // MARK: - Save

        /// Saves the carb ratio items to file storage and sets them as initial values.
        func saveCarbRatios() {
            let schedule = carbRatioItems.map { item in
                let time = timeFormatter.string(from: Date(timeIntervalSince1970: carbRatioTimeValues[item.timeIndex]))
                let offset = Int(carbRatioTimeValues[item.timeIndex] / 60)
                let value = carbRatioRateValues[item.rateIndex]
                return CarbRatioEntry(start: time, offset: offset, ratio: value)
            }
            fileStorage.save(CarbRatios(units: .grams, schedule: schedule), as: OpenAPS.Settings.carbRatios)
            initialCarbRatioItems = carbRatioItems
        }

        /// Saves the basal profile items to file storage and sets them as initial values.
        func saveBasalProfile() {
            let profile = basalProfileItems.map { item in
                let time = timeFormatter.string(from: Date(timeIntervalSince1970: basalProfileTimeValues[item.timeIndex]))
                let offset = Int(basalProfileTimeValues[item.timeIndex] / 60)
                let rate = basalProfileRateValues[item.rateIndex]
                return BasalProfileEntry(start: time, minutes: offset, rate: rate)
            }
            fileStorage.save(profile, as: OpenAPS.Settings.basalProfile)
            initialBasalProfileItems = basalProfileItems
        }

        /// Saves the insulin sensitivity (ISF) items to file storage and sets them as initial values.
        func saveISFValues() {
            let sensitivities = isfItems.map { item in
                let time = timeFormatter.string(from: Date(timeIntervalSince1970: isfTimeValues[item.timeIndex]))
                let offset = Int(isfTimeValues[item.timeIndex] / 60)
                let value = isfRateValues[item.rateIndex]
                return InsulinSensitivityEntry(sensitivity: value, offset: offset, start: time)
            }
            let profile = InsulinSensitivities(units: .mgdL, userPreferredUnits: .mgdL, sensitivities: sensitivities)
            fileStorage.save(profile, as: OpenAPS.Settings.insulinSensitivities)
            initialISFItems = isfItems
        }

        /// Saves the glucose target items to file storage and sets them as initial values.
        func saveTargets() {
            let targets = targetItems.map { item in
                let time = timeFormatter.string(from: Date(timeIntervalSince1970: targetTimeValues[item.timeIndex]))
                let offset = Int(targetTimeValues[item.timeIndex] / 60)
                let value = targetRateValues[item.lowIndex]
                return BGTargetEntry(low: value, high: value, start: time, offset: offset)
            }
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
            settingsManager.settings = settingsCopy
        }

        /// Applies the selected delivery preferences to the app's settings.
        func applyToPreferences() {
            var preferencesCopy = settingsManager.preferences
            preferencesCopy.maxIOB = maxIOB
            preferencesCopy.maxCOB = maxCOB
            settingsManager.preferences = preferencesCopy
        }

        /// Saves pump delivery limits to persistent storage and broadcasts changes.
        func applyToPumpSettings() {
            let defaultDIA = settingsProvider.settings.insulinPeakTime.value
            let pumpSettings = PumpSettings(insulinActionCurve: defaultDIA, maxBolus: maxBolus, maxBasal: maxBasal)
            fileStorage.save(pumpSettings, as: OpenAPS.Settings.settings)

            // TODO: Evaluate whether broadcasting this early is needed
            // DispatchQueue.main.async {
            //     self.broadcaster.notify(PumpSettingsObserver.self, on: DispatchQueue.main) {
            //         $0.pumpSettingsDidChange(pumpSettings)
            //     }
            // }
        }
    }
}

// MARK: - Protocol (optional) to unify type mapping

protocol TherapyItemConvertible {
    var rateIndex: Int { get }
    var timeIndex: Int { get }
}

extension ISFEditor.Item: TherapyItemConvertible {}
extension CarbRatioEditor.Item: TherapyItemConvertible {}
extension BasalProfileEditor.Item: TherapyItemConvertible {}
