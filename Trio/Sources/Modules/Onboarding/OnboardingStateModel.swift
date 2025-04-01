import Combine
import Foundation
import LoopKit
import Observation
import SwiftUI

/// Represents the different steps in the onboarding process.
enum OnboardingStep: Int, CaseIterable, Identifiable {
    case welcome
    case glucoseTarget
    case basalProfile
    case carbRatio
    case insulinSensitivity
    case completed

    var id: Int { rawValue }

    /// The title to display for this onboarding step.
    var title: String {
        switch self {
        case .welcome:
            return "Welcome to Trio"
        case .glucoseTarget:
            return "Glucose Target"
        case .basalProfile:
            return "Basal Profile"
        case .carbRatio:
            return "Carbohydrate Ratio"
        case .insulinSensitivity:
            return "Insulin Sensitivity"
        case .completed:
            return "All Set!"
        }
    }

    /// A detailed description of what this onboarding step is about.
    var description: String {
        switch self {
        case .welcome:
            return "Trio is a powerful app that helps you manage your diabetes. Let's get started by setting up a few important parameters that will help Trio work effectively for you."
        case .glucoseTarget:
            return "Your glucose target is the blood glucose level you aim to maintain. Trio will use this to calculate insulin doses and provide recommendations."
        case .basalProfile:
            return "Your basal profile represents the amount of background insulin you need throughout the day. This helps Trio calculate your insulin needs."
        case .carbRatio:
            return "Your carb ratio tells how many grams of carbohydrates one unit of insulin will cover. This is essential for accurate meal bolus calculations."
        case .insulinSensitivity:
            return "Your insulin sensitivity factor (ISF) indicates how much one unit of insulin will lower your blood glucose. This helps calculate correction boluses."
        case .completed:
            return "Great job! You've completed the initial setup of Trio. You can always adjust these settings later in the app."
        }
    }

    /// The system icon name associated with this step.
    var iconName: String {
        switch self {
        case .welcome:
            return "hand.wave.fill"
        case .glucoseTarget:
            return "target"
        case .basalProfile:
            return "chart.xyaxis.line"
        case .carbRatio:
            return "fork.knife"
        case .insulinSensitivity:
            return "drop.fill"
        case .completed:
            return "checkmark.circle.fill"
        }
    }

    /// Returns the next step in the onboarding process, or nil if this is the last step.
    var next: OnboardingStep? {
        let allCases = OnboardingStep.allCases
        let currentIndex = allCases.firstIndex(of: self) ?? 0
        let nextIndex = currentIndex + 1
        return nextIndex < allCases.count ? allCases[nextIndex] : nil
    }

    /// Returns the previous step in the onboarding process, or nil if this is the first step.
    var previous: OnboardingStep? {
        let allCases = OnboardingStep.allCases
        let currentIndex = allCases.firstIndex(of: self) ?? 0
        let previousIndex = currentIndex - 1
        return previousIndex >= 0 ? allCases[previousIndex] : nil
    }

    /// The accent color to use for this step.
    var accentColor: Color {
        switch self {
        case .welcome:
            return Color.blue
        case .glucoseTarget:
            return Color.green
        case .basalProfile:
            return Color.purple
        case .carbRatio:
            return Color.orange
        case .insulinSensitivity:
            return Color.red
        case .completed:
            return Color.blue
        }
    }
}

/// Model that holds the data collected during onboarding.
extension Onboarding {
    @Observable final class StateModel: BaseStateModel<Provider> {
        @ObservationIgnored @Injected() var storage: FileStorage!
        @ObservationIgnored @Injected() var deviceManager: DeviceDataManager!

        // Carb Ratio related
        var carbRatioItems: [CarbRatioEditor.Item] = []
        var initialCarbRatioItems: [CarbRatioEditor.Item] = []
        let carbRatioTimeValues = stride(from: 0.0, to: 1.days.timeInterval, by: 30.minutes.timeInterval).map { $0 }
        let carbRatioRateValues = stride(from: 30.0, to: 501.0, by: 1.0).map { ($0.decimal ?? .zero) / 10 }

        // Basal Profile related
        var initialBasalProfileItems: [BasalProfileEditor.Item] = []
        var basalProfileItems: [BasalProfileEditor.Item] = []
        let basalProfileTimeValues = stride(from: 0.0, to: 1.days.timeInterval, by: 30.minutes.timeInterval).map { $0 }
        var basalProfileRateValues: [Decimal] = stride(from: 0.05, to: 3.05, by: 0.05).map { Decimal($0) }

        // ISF related
        var isfItems: [ISFEditor.Item] = []
        var initialISFItems: [ISFEditor.Item] = []
        let isfTimeValues = stride(from: 0.0, to: 1.days.timeInterval, by: 30.minutes.timeInterval).map { $0 }
        var rateValues: [Decimal] {
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
            let settingsProvider = PickerSettingsProvider.shared
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
            applyToSettings()
        }

        /// Applies the onboarding data to the app's settings.
        func applyToSettings() {
            // Make a copy of the current settings that we can mutate
            var settingsCopy = settingsManager.settings

            // Apply glucose units
            settingsCopy.units = units

            // Apply targets
            saveTargets()

            // Apply basal profile
            // TODO: - should we use the return value or modify the function to not return anything?
            _ = saveBasalProfile()

            // Apply carb ratio
            saveCarbRatios()

            // Apply ISF values
            saveISFValues()

            // Instead of using updateSettings which doesn't exist,
            // we'll directly set the settings property which will trigger the didSet observer
            settingsManager.settings = settingsCopy
        }

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

        func getCarbRatioTherapyItems(from basalRates: [CarbRatioEditor.Item]) -> [TherapySettingItem] {
            basalRates.map {
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
        storage.save(profile, as: OpenAPS.Settings.carbRatios)
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
            let low = self.rateValues[item.lowIndex]
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
        storage.save(profile, as: OpenAPS.Settings.bgTargets)
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
            let rate = self.rateValues[item.rateIndex]
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
        storage.save(profile, as: OpenAPS.Settings.insulinSensitivities)
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

    func saveBasalProfile() -> AnyPublisher<Void, Error> {
        let profile = basalProfileItems.map { item -> BasalProfileEntry in
            let formatter = DateFormatter()
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "HH:mm:ss"
            let date = Date(timeIntervalSince1970: self.basalProfileTimeValues[item.timeIndex])
            let minutes = Int(date.timeIntervalSince1970 / 60)
            let rate = self.basalProfileRateValues[item.rateIndex]
            return BasalProfileEntry(start: formatter.string(from: date), minutes: minutes, rate: rate)
        }

        guard let pump = deviceManager?.pumpManager else {
            debugPrint("\(DebuggingIdentifiers.failed) No pump found; cannot save basal profile!")
            return Fail(error: NSError()).eraseToAnyPublisher()
        }

        let syncValues = profile.map {
            RepeatingScheduleValue(startTime: TimeInterval($0.minutes * 60), value: Double($0.rate))
        }

        return Future { promise in
            pump.syncBasalRateSchedule(items: syncValues) { result in
                switch result {
                case .success:
                    self.storage.save(profile, as: OpenAPS.Settings.basalProfile)
                    promise(.success(()))
                case let .failure(error):
                    promise(.failure(error))
                }
            }
        }.eraseToAnyPublisher()
    }
}
