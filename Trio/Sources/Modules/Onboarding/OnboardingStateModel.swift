import Combine
import Foundation
import LoopKit
import Observation
import SwiftUI

/// Represents the different steps in the onboarding process.
enum OnboardingStep: Int, CaseIterable, Identifiable {
    case welcome
    case unitSelection
    case glucoseTarget
    case basalProfile
    case carbRatio
    case insulinSensitivity
    case deliveryLimits
    case completed

    var id: Int { rawValue }

    var hasSubsteps: Bool {
        self == .deliveryLimits
    }

    var substeps: [DeliveryLimitSubstep] {
        guard hasSubsteps else { return [] }
        return DeliveryLimitSubstep.allCases
    }

    /// The title to display for this onboarding step.
    var title: String {
        switch self {
        case .welcome:
            return "Welcome to Trio"
        case .unitSelection:
            return "Units & Pump"
        case .glucoseTarget:
            return "Glucose Target"
        case .basalProfile:
            return "Basal Profile"
        case .carbRatio:
            return "Carbohydrate Ratio"
        case .insulinSensitivity:
            return "Insulin Sensitivity"
        case .deliveryLimits:
            return "Delivery Limits"
        case .completed:
            return "All Set!"
        }
    }

    /// A detailed description of what this onboarding step is about.
    var description: String {
        switch self {
        case .welcome:
            return "Trio is a powerful app that helps you manage your diabetes. Let's get started by setting up a few important parameters that will help Trio work effectively for you."
        case .unitSelection:
            return "Before you can begin with configuring your therapy settigns, Trio needs to know which units you use for your glucose and insulin measurements (based on your pump model)."
        case .glucoseTarget:
            return "Your glucose target is the blood glucose level you aim to maintain. Trio will use this to calculate insulin doses and provide recommendations."
        case .basalProfile:
            return "Your basal profile represents the amount of background insulin you need throughout the day. This helps Trio calculate your insulin needs."
        case .carbRatio:
            return "Your carb ratio tells how many grams of carbohydrates one unit of insulin will cover. This is essential for accurate meal bolus calculations."
        case .insulinSensitivity:
            return "Your insulin sensitivity factor (ISF) indicates how much one unit of insulin will lower your blood glucose. This helps calculate correction boluses."
        case .deliveryLimits:
            return "Trio offers various delivery limits which represent the maximum amount of insulin it can deliver at a time. This helps ensure safe and effective experience."
        case .completed:
            return "Great job! You've completed the initial setup of Trio. You can always adjust these settings later in the app."
        }
    }

    /// The system icon name associated with this step.
    var iconName: String {
        switch self {
        case .welcome:
            return "hand.wave.fill"
        case .unitSelection:
            return "numbers.rectangle"
        case .glucoseTarget:
            return "target"
        case .basalProfile:
            return "chart.xyaxis.line"
        case .carbRatio:
            return "fork.knife"
        case .insulinSensitivity:
            return "drop.fill"
        case .deliveryLimits:
            return "slider.horizontal.3"
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
        case .completed,
             .deliveryLimits,
             .unitSelection,
             .welcome:
            return Color.blue
        case .glucoseTarget:
            return Color.green
        case .basalProfile:
            return Color.purple
        case .carbRatio:
            return Color.orange
        case .insulinSensitivity:
            return Color.red
        }
    }
}

enum DeliveryLimitSubstep: Int, CaseIterable, Identifiable {
    case maxIOB
    case maxBolus
    case maxBasal
    case maxCOB

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .maxIOB: return String(localized: "Max IOB", comment: "Max IOB")
        case .maxBolus: return String(localized: "Max Bolus")
        case .maxBasal: return String(localized: "Max Basal")
        case .maxCOB: return String(localized: "Max COB", comment: "Max COB")
        }
    }

    var hint: String {
        switch self {
        case .maxIOB: return String(localized: "Maximum units of insulin allowed to be active.")
        case .maxBolus: return String(localized: "Largest bolus of insulin allowed.")
        case .maxBasal: return String(localized: "Largest basal rate allowed.")
        case .maxCOB: return String(localized: "Maximum Carbs On Board (COB) allowed.")
        }
    }

    var description: any View {
        switch self {
        case .maxIOB:
            return VStack(alignment: .leading, spacing: 8) {
                Text(
                    "This is the maximum amount of Insulin On Board (IOB) above profile basal rates from all sources - positive temporary basal rates, manual or meal boluses, and SMBs - that Trio is allowed to accumulate to address an above target glucose."
                )
                Text(
                    "If a calculated amount exceeds this limit, the suggested and / or delivered amount will be reduced so that active insulin on board (IOB) will not exceed this safety limit."
                )
                Text(
                    "Note: You can still manually bolus above this limit, but the suggested bolus amount will never exceed this in the bolus calculator."
                )
            }
        case .maxBolus:
            return VStack(alignment: .leading, spacing: 8) {
                Text(
                    "This is the maximum bolus allowed to be delivered at one time. This limits manual and automatic bolus."
                )
                Text("Most set this to their largest meal bolus. Then, adjust if needed.")
                Text("If you attempt to request a bolus larger than this, the bolus will not be accepted.")
            }
        case .maxBasal:
            return VStack(alignment: .leading, spacing: 8) {
                Text(
                    "This is the maximum basal rate allowed to be set or scheduled. This applies to both automatic and manual basal rates."
                )
                Text(
                    "Note to Medtronic Pump Users: You must also manually set the max basal rate on the pump to this value or higher."
                )
            }
        case .maxCOB:
            return VStack(alignment: .leading, spacing: 8) {
                Text(
                    "This setting defines the maximum amount of Carbs On Board (COB) at any given time for Trio to use in dosing calculations. If more carbs are entered than allowed by this limit, Trio will cap the current COB in calculations to Max COB and remain at max until all remaining carbs have shown to be absorbed."
                )
                Text(
                    "For example, if Max COB is 120 g and you enter a meal containing 150 g of carbs, your COB will remain at 120 g until the remaining 30 g have been absorbed."
                )
                Text("This is an important limit when UAM is ON.")
            }
        }
    }
}

enum PumpOptionsForOnboardingUnits: String, Equatable, CaseIterable, Identifiable {
    case minimed
    case omnipodEros
    case omnipodDash
    case dana

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .minimed:
            return "Medtronic 5xx / 7xx"
        case .omnipodEros:
            return "Omnipod Eros"
        case .omnipodDash:
            return "Omnipod Dash"
        case .dana:
            return "Dana (RS/-i)"
        }
    }
}

/// Model that holds the data collected during onboarding.
extension Onboarding {
    @Observable final class StateModel: BaseStateModel<Provider> {
        @ObservationIgnored @Injected() var fileStorage: FileStorage!
        @ObservationIgnored @Injected() var deviceManager: DeviceDataManager!
        @ObservationIgnored @Injected() private var broadcaster: Broadcaster!

        private let settingsProvider = PickerSettingsProvider.shared

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
