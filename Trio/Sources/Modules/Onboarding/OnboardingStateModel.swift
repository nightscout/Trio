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

        // Nightscout Setup
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

        // Carb Ratio related
        var carbRatioItems: [CarbRatioEditor.Item] = []
        var initialCarbRatioItems: [CarbRatioEditor.Item] = []
        let carbRatioTimeValues = stride(from: 0.0, to: 1.days.timeInterval, by: 30.minutes.timeInterval).map { $0 }
        let carbRatioRateValues = stride(from: 30.0, to: 501.0, by: 1.0).map { ($0.decimal ?? .zero) / 10 }

        // Basal Profile related
        var initialBasalProfileItems: [BasalProfileEditor.Item] = []
        var basalProfileItems: [BasalProfileEditor.Item] = []
        let basalProfileTimeValues = stride(from: 0.0, to: 1.days.timeInterval, by: 30.minutes.timeInterval).map { $0 }
        var basalProfileRateValues: [Decimal] {
            switch pumpModel {
            case .dana,
                 .minimed:
                return stride(from: 0.1, to: 30.0, by: 0.1).map { Decimal($0) }
            case .omnipodDash,
                 .omnipodEros:
                return stride(from: 0.05, to: 30.0, by: 0.05).map { Decimal($0) }
            }
        }

        // ISF related
        var isfItems: [ISFEditor.Item] = []
        var initialISFItems: [ISFEditor.Item] = []
        let isfTimeValues = stride(from: 0.0, to: 1.days.timeInterval, by: 30.minutes.timeInterval).map { $0 }
        var isfRateValues: [Decimal] {
            var values = stride(from: 9, to: 540.01, by: 1.0).map { Decimal($0) }

            if units == .mmolL {
                values = values.filter { Int(truncating: $0 as NSNumber) % 2 == 0 }
            }

            return values
        }

        // Target related
        var targetItems: [TargetsEditor.Item] = []
        var initialTargetItems: [TargetsEditor.Item] = []
        let targetTimeValues = stride(from: 0, to: 1.days.timeInterval, by: 30.minutes.timeInterval).map { $0 }

        var targetRateValues: [Decimal] {
            let glucoseSetting = PickerSetting(value: 0, step: 1, min: 72, max: 180, type: .glucose)
            return settingsProvider.generatePickerValues(from: glucoseSetting, units: units)
        }

        // Basal Profile
        var basalRates: [BasalRateEntry] = [BasalRateEntry(startTime: 0, rate: 1.0)]

        // Carb Ratio
        var carbRatio: Decimal = 10

        // Insulin Sensitivity Factor
        var isf: Decimal = 40

        // Blood Glucose Units
        var units: GlucoseUnits = .mgdL

        var pumpModel: PumpOptionsForOnboardingUnits = .omnipodDash

        var maxBolus: Decimal = 10
        var maxBasal: Decimal = 2
        var maxIOB: Decimal = 0
        var maxCOB: Decimal = 120

        struct BasalRateEntry: Identifiable {
            var id = UUID()
            var startTime: Int // Minutes from midnight
            var rate: Decimal

            var timeFormatted: String {
                let hours = startTime / 60
                let minutes = startTime % 60
                return String(format: "%02d:%02d", hours, minutes)
            }
        }

        override func subscribe() {
            // TODO: why are we immediately storing to settings?
//            saveOnboardingData()
        }

        func saveOnboardingData() {
            applyToSettings()
            applyToPreferences()
            applyToPumpSettings()
        }

        /// Applies the onboarding data to the app's settings.
        func applyToSettings() {
            // Make a copy of the current settings that we can mutate
            var settingsCopy = settingsManager.settings

            settingsCopy.units = units

            // Store therapy settings
            saveTargets()
            saveBasalProfile()
            saveCarbRatios()
            saveISFValues()

            // We'll directly set the settings property which will trigger the didSet observer
            settingsManager.settings = settingsCopy
        }

        func applyToPreferences() {
            var preferencesCopy = settingsManager.preferences

            preferencesCopy.maxIOB = maxIOB
            preferencesCopy.maxCOB = maxCOB

            // We'll directly set the preferences property which will trigger the didSet observer
            settingsManager.preferences = preferencesCopy
        }

        func applyToPumpSettings() {
            let defaultDIA = settingsProvider.settings.insulinPeakTime.value
            let pumpSettings = PumpSettings(insulinActionCurve: defaultDIA, maxBolus: maxBolus, maxBasal: maxBasal)
            fileStorage.save(pumpSettings, as: OpenAPS.Settings.settings)

            // TODO: is this actually necessary at this point? Nothing is set up yet, nothing is subscribed to this observer...
            DispatchQueue.main.async {
                self.broadcaster.notify(PumpSettingsObserver.self, on: DispatchQueue.main) {
                    $0.pumpSettingsDidChange(pumpSettings)
                }
            }
        }

        // TODO: clean up these function and unify them
        func getTargetTherapyItems(from targets: [TargetsEditor.Item]) -> [TherapySettingItem] {
            targets.map {
                TherapySettingItem(
                    id: UUID(),
                    time: targetTimeValues[$0.timeIndex],
                    value: Double(targetRateValues[$0.lowIndex])
                )
            }
        }

        func updateTargets(from therapyItems: [TherapySettingItem]) {
            targetItems = therapyItems.map { item in
                let timeIndex = targetTimeValues.firstIndex(where: { $0 == item.time }) ?? 0
                let closestRate = targetRateValues.enumerated().min(by: {
                    abs(Double($0.element) - item.value) < abs(Double($1.element) - item.value)
                })?.offset ?? 0

                return TargetsEditor.Item(lowIndex: closestRate, highIndex: closestRate, timeIndex: timeIndex)
            }
        }

        func getBasalTherapyItems(from basalRates: [BasalProfileEditor.Item]) -> [TherapySettingItem] {
            basalRates.map {
                TherapySettingItem(
                    id: UUID(),
                    time: basalProfileTimeValues[$0.timeIndex],
                    value: Double(basalProfileRateValues[$0.rateIndex])
                )
            }
        }

        func updateBasalRates(from therapyItems: [TherapySettingItem]) {
            basalProfileItems = therapyItems.map { item in
                let timeIndex = basalProfileTimeValues.firstIndex(where: { $0 == item.time }) ?? 0
                let closestRate = basalProfileRateValues.enumerated().min(by: {
                    abs(Double($0.element) - item.value) < abs(Double($1.element) - item.value)
                })?.offset ?? 0

                return BasalProfileEditor.Item(rateIndex: closestRate, timeIndex: timeIndex)
            }
        }

        func getCarbRatioTherapyItems(from carbRatios: [CarbRatioEditor.Item]) -> [TherapySettingItem] {
            carbRatios.map {
                TherapySettingItem(
                    id: UUID(),
                    time: carbRatioTimeValues[$0.timeIndex],
                    value: Double(carbRatioRateValues[$0.rateIndex])
                )
            }
        }

        func updateCarbRatios(from therapyItems: [TherapySettingItem]) {
            carbRatioItems = therapyItems.map { item in
                let timeIndex = carbRatioTimeValues.firstIndex(where: { $0 == item.time }) ?? 0
                let closestRate = carbRatioRateValues.enumerated().min(by: {
                    abs(Double($0.element) - item.value) < abs(Double($1.element) - item.value)
                })?.offset ?? 0

                return CarbRatioEditor.Item(rateIndex: closestRate, timeIndex: timeIndex)
            }
        }

        func getSensitivityTherapyItems(from sensitivities: [ISFEditor.Item]) -> [TherapySettingItem] {
            sensitivities.map {
                TherapySettingItem(
                    id: UUID(),
                    time: isfTimeValues[$0.timeIndex],
                    value: Double(isfRateValues[$0.rateIndex])
                )
            }
        }

        func updateSensitivies(from therapyItems: [TherapySettingItem]) {
            isfItems = therapyItems.map { item in
                let timeIndex = isfTimeValues.firstIndex(where: { $0 == item.time }) ?? 0
                let closestRate = isfRateValues.enumerated().min(by: {
                    abs(Double($0.element) - item.value) < abs(Double($1.element) - item.value)
                })?.offset ?? 0

                return ISFEditor.Item(rateIndex: closestRate, timeIndex: timeIndex)
            }
        }

        // TODO: add update handler for all therapy items to automatically fill in time gaps and ensure schedule always starts at 00:00 and ends at 23:30
    }
}

// MARK: - Setup Carb Ratios

extension Onboarding.StateModel {
    var carbRatiosHaveChanges: Bool {
        if initialCarbRatioItems.count != carbRatioItems.count {
            return true
        }

        for (initialItem, currentItem) in zip(initialCarbRatioItems, carbRatioItems) {
            if initialItem.rateIndex != currentItem.rateIndex || initialItem.timeIndex != currentItem.timeIndex {
                return true
            }
        }

        return false
    }

    func addCarbRatio() {
        var time = 0
        var rate = 0
        if let last = carbRatioItems.last {
            time = last.timeIndex + 1
            rate = last.rateIndex
        }

        let newItem = CarbRatioEditor.Item(rateIndex: rate, timeIndex: time)

        carbRatioItems.append(newItem)
    }

    func saveCarbRatios() {
        guard carbRatiosHaveChanges else { return }

        let schedule = carbRatioItems.enumerated().map { _, item -> CarbRatioEntry in
            let fotmatter = DateFormatter()
            fotmatter.timeZone = TimeZone(secondsFromGMT: 0)
            fotmatter.dateFormat = "HH:mm:ss"
            let date = Date(timeIntervalSince1970: self.carbRatioTimeValues[item.timeIndex])
            let minutes = Int(date.timeIntervalSince1970 / 60)
            let rate = self.carbRatioRateValues[item.rateIndex]
            return CarbRatioEntry(start: fotmatter.string(from: date), offset: minutes, ratio: rate)
        }
        let profile = CarbRatios(units: .grams, schedule: schedule)
        saveCarbRatioProfile(profile)
        initialCarbRatioItems = carbRatioItems.map { CarbRatioEditor.Item(rateIndex: $0.rateIndex, timeIndex: $0.timeIndex) }
    }

//    func validate() {
//        DispatchQueue.main.async {
//            let uniq = Array(Set(self.items))
//            let sorted = uniq.sorted { $0.timeIndex < $1.timeIndex }
//            sorted.first?.timeIndex = 0
//            if self.items != sorted {
//                self.items = sorted
//            }
//        }
//    }

    func saveCarbRatioProfile(_ profile: CarbRatios) {
        fileStorage.save(profile, as: OpenAPS.Settings.carbRatios)
    }
}

// MARK: - Setup glucose targets

extension Onboarding.StateModel {
    var targetsHaveChanged: Bool {
        initialTargetItems != targetItems
    }

    func addTarget() {
        var time = 0
        var low = 0
        var high = 0
        if let last = targetItems.last {
            time = last.timeIndex + 1
            low = last.lowIndex
            high = low
        }

        let newItem = TargetsEditor.Item(lowIndex: low, highIndex: high, timeIndex: time)

        targetItems.append(newItem)
    }

    func saveTargets() {
        guard targetsHaveChanged else { return }

        let targets = targetItems.map { item -> BGTargetEntry in
            let formatter = DateFormatter()
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "HH:mm:ss"
            let date = Date(timeIntervalSince1970: self.targetTimeValues[item.timeIndex])
            let minutes = Int(date.timeIntervalSince1970 / 60)
            let low = self.isfRateValues[item.lowIndex]
            let high = low
            return BGTargetEntry(low: low, high: high, start: formatter.string(from: date), offset: minutes)
        }
        let profile = BGTargets(units: .mgdL, userPreferredUnits: .mgdL, targets: targets)
        saveTargets(profile)
        initialTargetItems = targetItems
            .map { TargetsEditor.Item(lowIndex: $0.lowIndex, highIndex: $0.highIndex, timeIndex: $0.timeIndex) }
    }

//    func validateTarget() {
//        DispatchQueue.main.async {
//            let uniq = Array(Set(self.items))
//            let sorted = uniq.sorted { $0.timeIndex < $1.timeIndex }
//                .map { item -> Item in
//                    Item(lowIndex: item.lowIndex, highIndex: item.highIndex, timeIndex: item.timeIndex)
//                }
//            sorted.first?.timeIndex = 0
//            self.items = sorted
//
//            if self.items.isEmpty {
//                self.units = self.settingsManager.settings.units
//            }
//        }
//    }

    func saveTargets(_ profile: BGTargets) {
        fileStorage.save(profile, as: OpenAPS.Settings.bgTargets)
    }
}

// MARK: - Setup ISF values

extension Onboarding.StateModel {
    var isfValuesHaveChanges: Bool {
        initialISFItems != isfItems
    }

    func addISFValue() {
        var time = 0
        var rate = 0
        if let last = isfItems.last {
            time = last.timeIndex + 1
            rate = last.rateIndex
        }

        let newItem = ISFEditor.Item(rateIndex: rate, timeIndex: time)

        isfItems.append(newItem)
    }

    func saveISFValues() {
        guard isfValuesHaveChanges else { return }

        let sensitivities = isfItems.map { item -> InsulinSensitivityEntry in
            let fotmatter = DateFormatter()
            fotmatter.timeZone = TimeZone(secondsFromGMT: 0)
            fotmatter.dateFormat = "HH:mm:ss"
            let date = Date(timeIntervalSince1970: self.isfTimeValues[item.timeIndex])
            let minutes = Int(date.timeIntervalSince1970 / 60)
            let rate = self.isfRateValues[item.rateIndex]
            return InsulinSensitivityEntry(sensitivity: rate, offset: minutes, start: fotmatter.string(from: date))
        }
        let profile = InsulinSensitivities(
            units: .mgdL,
            userPreferredUnits: .mgdL,
            sensitivities: sensitivities
        )
        saveISFProfile(profile)
        initialISFItems = isfItems.map { ISFEditor.Item(rateIndex: $0.rateIndex, timeIndex: $0.timeIndex) }
    }

//    func validate() {
//        DispatchQueue.main.async {
//            DispatchQueue.main.async {
//                let uniq = Array(Set(self.items))
//                let sorted = uniq.sorted { $0.timeIndex < $1.timeIndex }
//                sorted.first?.timeIndex = 0
//                if self.items != sorted {
//                    self.items = sorted
//                }
//                if self.items.isEmpty {
//                    self.units = self.settingsManager.settings.units
//                }
//            }
//        }
//    }

    func saveISFProfile(_ profile: InsulinSensitivities) {
        fileStorage.save(profile, as: OpenAPS.Settings.insulinSensitivities)
    }
}

// MARK: - Setup Basal Profile

extension Onboarding.StateModel {
    var hasBasalProfileChanges: Bool {
        if initialBasalProfileItems.count != basalProfileItems.count {
            return true
        }

        for (initialItem, currentItem) in zip(initialBasalProfileItems, basalProfileItems) {
            if initialItem.rateIndex != currentItem.rateIndex || initialItem.timeIndex != currentItem.timeIndex {
                return true
            }
        }

        return false
    }

    func addBasalRate() {
        var time = 0
        var rate = 20 // Default to 1.0 U/h (index 20 if basalProfileRateValues starts at 0.05 and increments by 0.05)

        if let last = basalProfileItems.last {
            time = last.timeIndex + 1
            rate = last.rateIndex
        }

        let newItem = BasalProfileEditor.Item(rateIndex: rate, timeIndex: time)
        basalProfileItems.append(newItem)
    }

    func saveBasalProfile() {
        let profile = basalProfileItems.map { item -> BasalProfileEntry in
            let formatter = DateFormatter()
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "HH:mm:ss"
            let date = Date(timeIntervalSince1970: self.basalProfileTimeValues[item.timeIndex])
            let minutes = Int(date.timeIntervalSince1970 / 60)
            let rate = self.basalProfileRateValues[item.rateIndex]
            return BasalProfileEntry(start: formatter.string(from: date), minutes: minutes, rate: rate)
        }

        fileStorage.save(profile, as: OpenAPS.Settings.basalProfile)
    }
}
