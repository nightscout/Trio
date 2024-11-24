import Combine
import CoreData
import Observation
import SwiftUI

extension Adjustments {
    @Observable final class StateModel: BaseStateModel<Provider> {
        @ObservationIgnored @Injected() var broadcaster: Broadcaster!
        @ObservationIgnored @Injected() var tempTargetStorage: TempTargetsStorage!
        @ObservationIgnored @Injected() var apsManager: APSManager!
        @ObservationIgnored @Injected() var overrideStorage: OverrideStorage!
        @ObservationIgnored @Injected() var nightscoutManager: NightscoutManager!

        var overridePercentage: Double = 100
        var isEnabled = false
        var indefinite = true
        var overrideDuration: Decimal = 0
        var target: Decimal = 0
        var currentGlucoseTarget: Decimal = 100
        var shouldOverrideTarget: Bool = false
        var smbIsOff: Bool = false
        var id = ""
        var overrideName: String = ""
        var isPreset: Bool = false
        var overridePresets: [OverrideStored] = []
        var advancedSettings: Bool = false
        var isfAndCr: Bool = true
        var isf: Bool = true
        var cr: Bool = true
        var smbIsScheduledOff: Bool = false
        var start: Decimal = 0
        var end: Decimal = 0
        var smbMinutes: Decimal = 0
        var uamMinutes: Decimal = 0
        var defaultSmbMinutes: Decimal = 0
        var defaultUamMinutes: Decimal = 0
        var selectedTab: Tab = .overrides
        var activeOverrideName: String = ""
        var currentActiveOverride: OverrideStored?
        var activeTempTargetName: String = ""

        var currentActiveTempTarget: TempTargetStored?
        var showOverrideEditSheet = false
        var showTempTargetEditSheet = false
        var units: GlucoseUnits = .mgdL

        // temp target stuff
        let normalTarget: Decimal = 100
        var tempTargetDuration: Decimal = 0
        var tempTargetName: String = ""
        var tempTargetTarget: Decimal = 100
        var isTempTargetEnabled: Bool = false
        var date = Date()
        var newPresetName = ""
        var tempTargetPresets: [TempTargetStored] = []
        var scheduledTempTargets: [TempTargetStored] = []
        var percentage: Double = 100
        var maxValue: Decimal = 1.2
        var halfBasalTarget: Decimal = 160
        var settingHalfBasalTarget: Decimal = 160
        var highTTraisesSens: Bool = false
        var isExerciseModeActive: Bool = false
        var lowTTlowersSens: Bool = false
        var didSaveSettings: Bool = false

        let coredataContext = CoreDataStack.shared.newTaskContext()
        let viewContext = CoreDataStack.shared.persistentContainer.viewContext

        var isHelpSheetPresented: Bool = false
        var helpSheetDetent = PresentationDetent.large

        private var cancellables = Set<AnyCancellable>()

        override func subscribe() {
            setupNotification()
            setupSettings()
            broadcaster.register(SettingsObserver.self, observer: self)
            broadcaster.register(PreferencesObserver.self, observer: self)

            Task {
                await withTaskGroup(of: Void.self) { group in
                    group.addTask {
                        self.setupOverridePresetsArray()
                    }
                    group.addTask {
                        self.setupTempTargetPresetsArray()
                    }
                    group.addTask {
                        self.updateLatestOverrideConfiguration()
                    }
                    group.addTask {
                        self.updateLatestTempTargetConfiguration()
                    }
                }
            }
        }

        func getCurrentGlucoseTarget() async {
            let now = Date()
            let calendar = Calendar.current
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "HH:mm:ss"
            dateFormatter.timeZone = TimeZone.current

            let bgTargets = await provider.getBGTarget()
            let entries: [(start: String, value: Decimal)] = bgTargets.targets.map { ($0.start, $0.low) }

            for (index, entry) in entries.enumerated() {
                guard let entryTime = dateFormatter.date(from: entry.start) else {
                    print("Invalid entry start time: \(entry.start)")
                    continue
                }

                let entryComponents = calendar.dateComponents([.hour, .minute, .second], from: entryTime)
                let entryStartTime = calendar.date(
                    bySettingHour: entryComponents.hour!,
                    minute: entryComponents.minute!,
                    second: entryComponents.second!,
                    of: now
                )!

                let entryEndTime: Date
                if index < entries.count - 1,
                   let nextEntryTime = dateFormatter.date(from: entries[index + 1].start)
                {
                    let nextEntryComponents = calendar.dateComponents([.hour, .minute, .second], from: nextEntryTime)
                    entryEndTime = calendar.date(
                        bySettingHour: nextEntryComponents.hour!,
                        minute: nextEntryComponents.minute!,
                        second: nextEntryComponents.second!,
                        of: now
                    )!
                } else {
                    entryEndTime = calendar.date(byAdding: .day, value: 1, to: entryStartTime)!
                }

                if now >= entryStartTime, now < entryEndTime {
                    await MainActor.run {
                        currentGlucoseTarget = entry.value
                        target = currentGlucoseTarget
                    }
                    return
                }
            }
        }

        private func setupSettings() {
            units = settingsManager.settings.units
            defaultSmbMinutes = settingsManager.preferences.maxSMBBasalMinutes
            defaultUamMinutes = settingsManager.preferences.maxUAMSMBBasalMinutes
            maxValue = settingsManager.preferences.autosensMax
            settingHalfBasalTarget = settingsManager.preferences.halfBasalExerciseTarget
            halfBasalTarget = settingsManager.preferences.halfBasalExerciseTarget
            highTTraisesSens = settingsManager.preferences.highTemptargetRaisesSensitivity
            isExerciseModeActive = settingsManager.preferences.exerciseMode
            lowTTlowersSens = settingsManager.preferences.lowTemptargetLowersSensitivity
            percentage = computeAdjustedPercentage()
            Task {
                await getCurrentGlucoseTarget()
            }
        }
    }
}

// MARK: - Setup Notifications

extension Adjustments.StateModel {
    // Custom Notification to update View when an Override has been cancelled via Home View
    func setupNotification() {
        Foundation.NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleOverrideConfigurationUpdate),
            name: .didUpdateOverrideConfiguration,
            object: nil
        )

        // Custom Notification to update View when an Temp Target has been cancelled via Home View
        Foundation.NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleTempTargetConfigurationUpdate),
            name: .didUpdateTempTargetConfiguration,
            object: nil
        )

        // Creates a publisher that updates the Override View when the Custom notification was sent (via shortcut)
        Foundation.NotificationCenter.default.publisher(for: .willUpdateOverrideConfiguration)
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.updateLatestOverrideConfiguration()
            }
            .store(in: &cancellables)

        // Creates a publisher that updates the Temp Target View when the Custom notification was sent (via shortcut)
        Foundation.NotificationCenter.default.publisher(for: .willUpdateTempTargetConfiguration)
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.updateLatestTempTargetConfiguration()
            }
            .store(in: &cancellables)
    }

    @objc private func handleOverrideConfigurationUpdate() {
        updateLatestOverrideConfiguration()
    }

    @objc private func handleTempTargetConfigurationUpdate() {
        updateLatestTempTargetConfiguration()
    }

    func reorderOverride(from source: IndexSet, to destination: Int) {
        overridePresets.move(fromOffsets: source, toOffset: destination)

        for (index, override) in overridePresets.enumerated() {
            override.orderPosition = Int16(index + 1)
        }

        do {
            guard viewContext.hasChanges else { return }
            try viewContext.save()

            // Update Presets View
            setupOverridePresetsArray()

            Task {
                await nightscoutManager.uploadProfiles()
            }
        } catch {
            debugPrint(
                "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to save after reordering Override Presets with error: \(error.localizedDescription)"
            )
        }
    }

    func reorderTempTargets(from source: IndexSet, to destination: Int) {
        tempTargetPresets.move(fromOffsets: source, toOffset: destination)

        for (index, tempTarget) in tempTargetPresets.enumerated() {
            tempTarget.orderPosition = Int16(index + 1)
        }

        do {
            guard viewContext.hasChanges else { return }
            try viewContext.save()

            // Update Presets View
            setupTempTargetPresetsArray()
        } catch {
            debugPrint(
                "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to save after reordering Temp Target Presets with error: \(error.localizedDescription)"
            )
        }
    }
}

extension Adjustments.StateModel: SettingsObserver, PreferencesObserver {
    func settingsDidChange(_: FreeAPSSettings) {
        units = settingsManager.settings.units
        Task {
            await getCurrentGlucoseTarget()
        }
    }

    func preferencesDidChange(_: Preferences) {
        defaultSmbMinutes = settingsManager.preferences.maxSMBBasalMinutes
        defaultUamMinutes = settingsManager.preferences.maxUAMSMBBasalMinutes
        maxValue = settingsManager.preferences.autosensMax
        settingHalfBasalTarget = settingsManager.preferences.halfBasalExerciseTarget
        halfBasalTarget = settingsManager.preferences.halfBasalExerciseTarget
        highTTraisesSens = settingsManager.preferences.highTemptargetRaisesSensitivity
        isExerciseModeActive = settingsManager.preferences.exerciseMode
        lowTTlowersSens = settingsManager.preferences.lowTemptargetLowersSensitivity
        percentage = computeAdjustedPercentage()
        Task {
            await getCurrentGlucoseTarget()
        }
    }
}

extension PickerSettingsProvider {
    func generatePickerValues(from setting: PickerSetting, units: GlucoseUnits, roundMinToStep: Bool) -> [Decimal] {
        if !roundMinToStep {
            return generatePickerValues(from: setting, units: units)
        }

        // Adjust min to be divisible by step
        var newSetting = setting
        var min = Double(newSetting.min)
        let step = Double(newSetting.step)
        let remainder = min.truncatingRemainder(dividingBy: step)
        if remainder != 0 {
            // Move min up to the next value divisible by targetStep
            min += (step - remainder)
        }

        newSetting.min = Decimal(min)

        return generatePickerValues(from: newSetting, units: units)
    }
}

func percentageDescription(_ percent: Double) -> Text? {
    if percent.isNaN || percent == 100 { return nil }

    var description: String = "Insulin doses will be "

    if percent < 100 {
        description += "decreased by "
    } else {
        description += "increased by "
    }

    let deviationFrom100 = abs(percent - 100)
    description += String(format: "%.0f% %.", deviationFrom100)

    return Text(description)
}

// Function to check if the phone is using 24-hour format
func is24HourFormat() -> Bool {
    let formatter = DateFormatter()
    formatter.locale = Locale.current
    formatter.dateStyle = .none
    formatter.timeStyle = .short
    let dateString = formatter.string(from: Date())

    return !dateString.contains("AM") && !dateString.contains("PM")
}

// Helper function to convert hours to AM/PM format
func convertTo12HourFormat(_ hour: Int) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "h a"

    // Create a date from the hour and format it to AM/PM
    let calendar = Calendar.current
    let components = DateComponents(hour: hour)
    let date = calendar.date(from: components) ?? Date()

    return formatter.string(from: date)
}

// Helper function to format 24-hour numbers as two digits
func format24Hour(_ hour: Int) -> String {
    String(format: "%02d", hour)
}

func formatHrMin(_ durationInMinutes: Int) -> String {
    let hours = durationInMinutes / 60
    let minutes = durationInMinutes % 60

    switch (hours, minutes) {
    case let (0, m):
        return "\(m) min"
    case let (h, 0):
        return "\(h) hr"
    default:
        return "\(hours) hr \(minutes) min"
    }
}

func convertToMinutes(_ hours: Int, _ minutes: Int) -> Decimal {
    let totalMinutes = (hours * 60) + minutes
    return Decimal(max(0, totalMinutes))
}
