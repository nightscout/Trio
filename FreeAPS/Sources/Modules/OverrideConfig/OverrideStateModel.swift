import Combine
import CoreData
import Observation
import SwiftUI

extension OverrideConfig {
    @Observable final class StateModel: BaseStateModel<Provider> {
        @ObservationIgnored @Injected() var broadcaster: Broadcaster!
        @ObservationIgnored @Injected() var storage: TempTargetsStorage!
        @ObservationIgnored @Injected() var apsManager: APSManager!
        @ObservationIgnored @Injected() var overrideStorage: OverrideStorage!
        @ObservationIgnored @Injected() var nightscoutManager: NightscoutManager!

        var overridePercentage: Double = 100
        var isEnabled = false
        var indefinite = true
        var overrideDuration: Decimal = 0
        var target: Decimal = 100
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
        var showOverrideEditSheet = false

        var units: GlucoseUnits = .mgdL

        // temp target stuff
        var low: Decimal = 0
        var high: Decimal = 0
        var durationTT: Decimal = 0
        var date = Date()
        var newPresetName = ""
        var presetsTT: [TempTarget] = []
        var percentageTT = 100.0
        var maxValue: Decimal = 1.2
        var viewPercantage = false
        var hbt: Double = 160
        var didSaveSettings: Bool = false

        var isHelpSheetPresented: Bool = false
        var helpSheetDetent = PresentationDetent.large

        var alertMessage: String {
            let target: String = units == .mgdL ? "70-270 mg/dl" : "4-15 mmol/l"
            return "Please enter a valid target between" + " \(target)."
        }

        private var cancellables = Set<AnyCancellable>()

        override func subscribe() {
            setupNotification()
            units = settingsManager.settings.units
            defaultSmbMinutes = settingsManager.preferences.maxSMBBasalMinutes
            defaultUamMinutes = settingsManager.preferences.maxUAMSMBBasalMinutes
            setupOverridePresetsArray()
            updateLatestOverrideConfiguration()
            presetsTT = storage.presets()
            maxValue = settingsManager.preferences.autosensMax
            broadcaster.register(SettingsObserver.self, observer: self)
        }

        let coredataContext = CoreDataStack.shared.newTaskContext()
        let viewContext = CoreDataStack.shared.persistentContainer.viewContext
    }
}

// MARK: - Setup Notifications

extension OverrideConfig.StateModel {
    // Custom Notification to update View when an Override has been cancelled via Home View
    func setupNotification() {
        Foundation.NotificationCenter.default.publisher(for: .willUpdateOverrideConfiguration)
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.updateLatestOverrideConfiguration()
            }
            .store(in: &cancellables)
    }

    // MARK: - Enact Overrides

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

    /// here we only have to update the Boolean Flag 'enabled'
    @MainActor func enactOverridePreset(withID id: NSManagedObjectID) async {
        do {
            /// get the underlying NSManagedObject of the Override that should be enabled
            let overrideToEnact = try viewContext.existingObject(with: id) as? OverrideStored
            overrideToEnact?.enabled = true
            overrideToEnact?.date = Date()
            overrideToEnact?.isUploadedToNS = false

            /// Update the 'Cancel Override' button state
            isEnabled = true

            /// disable all active Overrides and reset state variables
            /// do not create a OverrideRunEntry because we only want that if we cancel a running Override, not when enacting a Preset
            await disableAllActiveOverrides(except: id, createOverrideRunEntry: currentActiveOverride != nil)

            await resetStateVariables()

            guard viewContext.hasChanges else { return }
            try viewContext.save()

            // Update View
            updateLatestOverrideConfiguration()
        } catch {
            debugPrint("\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to enact Override Preset")
        }
    }

    // MARK: - Save the Override that we want to cancel to the OverrideRunStored Entity, then cancel ALL active overrides

    @MainActor func disableAllActiveOverrides(except overrideID: NSManagedObjectID? = nil, createOverrideRunEntry: Bool) async {
        // Get ALL NSManagedObject IDs of ALL active Override to cancel every single Override
        let ids = await overrideStorage.loadLatestOverrideConfigurations(fetchLimit: 0) // 0 = no fetch limit

        await viewContext.perform {
            do {
                // Fetch the existing OverrideStored objects from the context
                let results = try ids.compactMap { id in
                    try self.viewContext.existingObject(with: id) as? OverrideStored
                }

                // If there are no results, return early
                guard !results.isEmpty else { return }

                // Check if we also need to create a corresponding OverrideRunStored entry, i.e. when the User uses the Cancel Button in Override View
                if createOverrideRunEntry {
                    // Use the first override to create a new OverrideRunStored entry
                    if let canceledOverride = results.first {
                        let newOverrideRunStored = OverrideRunStored(context: self.viewContext)
                        newOverrideRunStored.id = UUID()
                        newOverrideRunStored.name = canceledOverride.name
                        newOverrideRunStored.startDate = canceledOverride.date ?? .distantPast
                        newOverrideRunStored.endDate = Date()
                        newOverrideRunStored
                            .target = NSDecimalNumber(decimal: self.overrideStorage.calculateTarget(override: canceledOverride))
                        newOverrideRunStored.override = canceledOverride
                        newOverrideRunStored.isUploadedToNS = false
                    }
                }

                // Disable all override except the one with overrideID
                for overrideToCancel in results {
                    if overrideToCancel.objectID != overrideID {
                        overrideToCancel.enabled = false
                    }
                }

                // Save the context if there are changes
                if self.viewContext.hasChanges {
                    try self.viewContext.save()

                    // Update the View
                    self.updateLatestOverrideConfiguration()
                }
            } catch {
                debugPrint(
                    "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to disable active Overrides with error: \(error.localizedDescription)"
                )
            }
        }
    }

    // MARK: - Override (presets) save operations

    // Saves a Custom Override in a background context
    /// not a Preset
    func saveCustomOverride() async {
        let override = Override(
            name: overrideName,
            enabled: true,
            date: Date(),
            duration: overrideDuration,
            indefinite: indefinite,
            percentage: overridePercentage,
            smbIsOff: smbIsOff,
            isPreset: isPreset,
            id: id,
            overrideTarget: shouldOverrideTarget,
            target: target,
            advancedSettings: advancedSettings,
            isfAndCr: isfAndCr,
            isf: isf,
            cr: cr,
            smbIsScheduledOff: smbIsScheduledOff,
            start: start,
            end: end,
            smbMinutes: smbMinutes,
            uamMinutes: uamMinutes
        )

        // First disable all Overrides
        await disableAllActiveOverrides(createOverrideRunEntry: true)

        // Then save and activate a new custom Override and reset the State variables
        async let storeOverride: () = overrideStorage.storeOverride(override: override)
        async let resetState: () = resetStateVariables()

        _ = await (storeOverride, resetState)

        // Update View
        updateLatestOverrideConfiguration()
    }

    // Save Presets
    /// enabled has to be false, isPreset has to be true
    func saveOverridePreset() async {
        let preset = Override(
            name: overrideName,
            enabled: false,
            date: Date(),
            duration: overrideDuration,
            indefinite: indefinite,
            percentage: overridePercentage,
            smbIsOff: smbIsOff,
            isPreset: true,
            id: id,
            overrideTarget: shouldOverrideTarget,
            target: target,
            advancedSettings: advancedSettings,
            isfAndCr: isfAndCr,
            isf: isf,
            cr: cr,
            smbIsScheduledOff: smbIsScheduledOff,
            start: start,
            end: end,
            smbMinutes: smbMinutes,
            uamMinutes: uamMinutes
        )

        async let storeOverride: () = overrideStorage.storeOverride(override: preset)
        async let resetState: () = resetStateVariables()

        _ = await (storeOverride, resetState)

        // Update Presets View
        setupOverridePresetsArray()

        await nightscoutManager.uploadProfiles()
    }

    // MARK: - Setup Override Presets Array

    // Fill the array of the Override Presets to display them in the UI
    private func setupOverridePresetsArray() {
        Task {
            let ids = await self.overrideStorage.fetchForOverridePresets()
            await updateOverridePresetsArray(with: ids)
        }
    }

    @MainActor private func updateOverridePresetsArray(with IDs: [NSManagedObjectID]) async {
        do {
            let overrideObjects = try IDs.compactMap { id in
                try viewContext.existingObject(with: id) as? OverrideStored
            }
            overridePresets = overrideObjects
        } catch {
            debugPrint(
                "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to extract Overrides as NSManagedObjects from the NSManagedObjectIDs with error: \(error.localizedDescription)"
            )
        }
    }

    // MARK: - Override Preset Deletion

    func invokeOverridePresetDeletion(_ objectID: NSManagedObjectID) async {
        await overrideStorage.deleteOverridePreset(objectID)

        // Update Presets View
        setupOverridePresetsArray()

        await nightscoutManager.uploadProfiles()
    }

    // MARK: - Setup the State variables with the last Override configuration

    /// First get the latest Overrides corresponding NSManagedObjectID with a background fetch
    /// Then unpack it on the view context and update the State variables which can be used on in the View for some Logic
    /// This also needs to be called when we cancel an Override via the Home View to update the State of the Button for this case
    func updateLatestOverrideConfiguration() {
        Task {
            let id = await overrideStorage.loadLatestOverrideConfigurations(fetchLimit: 1)
            async let updateState: () = updateLatestOverrideConfigurationOfState(from: id)
            async let setOverride: () = setCurrentOverride(from: id)

            _ = await (updateState, setOverride)
        }
    }

    @MainActor func updateLatestOverrideConfigurationOfState(from IDs: [NSManagedObjectID]) async {
        do {
            let result = try IDs.compactMap { id in
                try viewContext.existingObject(with: id) as? OverrideStored
            }
            isEnabled = result.first?.enabled ?? false

            if !isEnabled {
                await resetStateVariables()
            }
        } catch {
            debugPrint(
                "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to updateLatestOverrideConfiguration"
            )
        }
    }

    // Sets the current active Preset name to show in the UI
    @MainActor func setCurrentOverride(from IDs: [NSManagedObjectID]) async {
        do {
            guard let firstID = IDs.first else {
                activeOverrideName = "Custom Override"
                currentActiveOverride = nil
                return
            }

            if let overrideToEdit = try viewContext.existingObject(with: firstID) as? OverrideStored {
                currentActiveOverride = overrideToEdit
                activeOverrideName = overrideToEdit.name ?? "Custom Override"
            }
        } catch {
            debugPrint(
                "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to set active preset name with error: \(error.localizedDescription)"
            )
        }
    }

    @MainActor func duplicateOverridePresetAndCancelPreviousOverride() async {
        // We get the current active Preset by using currentActiveOverride which can either be a Preset or a custom Override
        guard let overridePresetToDuplicate = currentActiveOverride, overridePresetToDuplicate.isPreset == true else { return }

        // Copy the current Override-Preset to not edit the underlying Preset
        let duplidateId = await overrideStorage.copyRunningOverride(overridePresetToDuplicate)

        // Cancel the duplicated Override
        /// As we are on the Main Thread already we don't need to cancel via the objectID in this case
        do {
            try await viewContext.perform {
                overridePresetToDuplicate.enabled = false

                guard self.viewContext.hasChanges else { return }
                try self.viewContext.save()
            }

            // Update View
            // TODO: -
            if let overrideToEdit = try viewContext.existingObject(with: duplidateId) as? OverrideStored
            {
                currentActiveOverride = overrideToEdit
                activeOverrideName = overrideToEdit.name ?? "Custom Override"
            }
        } catch {
            debugPrint(
                "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to cancel previous override with error: \(error.localizedDescription)"
            )
        }
    }

    // MARK: - Helper functions for Overrides

    @MainActor func resetStateVariables() async {
        id = ""

        overrideDuration = 0
        indefinite = true
        overridePercentage = 100
        advancedSettings = false
        smbIsOff = false
        overrideName = ""
        shouldOverrideTarget = false
        isf = true
        cr = true
        isfAndCr = true
        smbIsScheduledOff = false
        start = 0
        end = 0
        smbMinutes = defaultSmbMinutes
        uamMinutes = defaultUamMinutes
        target = 100
    }

    static func roundTargetToStep(_ target: Decimal, _ step: Decimal) -> Decimal {
        // Convert target and step to NSDecimalNumber
        guard let targetValue = NSDecimalNumber(decimal: target).doubleValue as Double?,
              let stepValue = NSDecimalNumber(decimal: step).doubleValue as Double?
        else {
            return target
        }

        // Perform the remainder check using truncatingRemainder
        let remainder = Decimal(targetValue.truncatingRemainder(dividingBy: stepValue))

        if remainder != 0 {
            // Calculate how much to adjust (up or down) based on the remainder
            let adjustment = step - remainder
            return target + adjustment
        }

        // Return the original target if no adjustment is needed
        return target
    }

    static func roundOverridePercentageToStep(_ percentage: Double, _ step: Int) -> Double {
        let stepDouble = Double(step)
        // Check if overridePercentage is not divisible by the selected step
        if percentage.truncatingRemainder(dividingBy: stepDouble) != 0 {
            let roundedValue: Double

            if percentage > 100 {
                // Round down to the nearest valid step away from 100
                let stepCount = (percentage - 100) / stepDouble
                roundedValue = 100 + floor(stepCount) * stepDouble
            } else {
                // Round up to the nearest valid step away from 100
                let stepCount = (100 - percentage) / stepDouble
                roundedValue = 100 - floor(stepCount) * stepDouble
            }

            // Ensure the value stays between 10 and 200
            return max(10, min(roundedValue, 200))
        }

        return percentage
    }
}

// MARK: - TEMP TARGET

extension OverrideConfig.StateModel {
    func enact() {
        guard durationTT > 0 else {
            return
        }
        var lowTarget = low

        if viewPercantage {
            lowTarget = Decimal(round(Double(computeTarget())))
            coredataContext.performAndWait {
                let saveToCoreData = TempTargets(context: self.coredataContext)
                saveToCoreData.id = UUID().uuidString
                saveToCoreData.active = true
                saveToCoreData.hbt = hbt
                saveToCoreData.date = Date()
                saveToCoreData.duration = durationTT as NSDecimalNumber
                saveToCoreData.startDate = Date()
                try? self.coredataContext.save()
            }
            didSaveSettings = true
        } else {
            coredataContext.performAndWait {
                let saveToCoreData = TempTargets(context: coredataContext)
                saveToCoreData.active = false
                saveToCoreData.date = Date()
                do {
                    guard coredataContext.hasChanges else { return }
                    try coredataContext.save()
                } catch {
                    print(error.localizedDescription)
                }
            }
        }
        var highTarget = lowTarget

        if units == .mmolL, !viewPercantage {
            lowTarget = Decimal(round(Double(lowTarget)))
            highTarget = lowTarget
        }

        let entry = TempTarget(
            name: TempTarget.custom,
            createdAt: date,
            targetTop: highTarget,
            targetBottom: lowTarget,
            duration: durationTT,
            enteredBy: TempTarget.manual,
            reason: TempTarget.custom
        )
        storage.storeTempTargets([entry])
        showModal(for: nil)
    }

    func cancel() {
        storage.storeTempTargets([TempTarget.cancel(at: Date())])
        showModal(for: nil)

        coredataContext.performAndWait {
            let saveToCoreData = TempTargets(context: self.coredataContext)
            saveToCoreData.active = false
            saveToCoreData.date = Date()
            do {
                guard coredataContext.hasChanges else { return }
                try coredataContext.save()
            } catch {
                print(error.localizedDescription)
            }

            let setHBT = TempTargetsSlider(context: self.coredataContext)
            setHBT.enabled = false
            setHBT.date = Date()
            do {
                guard coredataContext.hasChanges else { return }
                try coredataContext.save()
            } catch {
                print(error.localizedDescription)
            }
        }
    }

    func save() {
        guard durationTT > 0 else {
            return
        }
        var lowTarget = low

        if viewPercantage {
            lowTarget = Decimal(round(Double(computeTarget())))
            didSaveSettings = true
        }
        var highTarget = lowTarget

        if units == .mmolL, !viewPercantage {
            lowTarget = Decimal(round(Double(lowTarget.asMgdL)))
            highTarget = lowTarget
        }

        let entry = TempTarget(
            name: newPresetName.isEmpty ? TempTarget.custom : newPresetName,
            createdAt: Date(),
            targetTop: highTarget,
            targetBottom: lowTarget,
            duration: durationTT,
            enteredBy: TempTarget.manual,
            reason: newPresetName.isEmpty ? TempTarget.custom : newPresetName
        )
        presetsTT.append(entry)
        storage.storePresets(presetsTT)

        if viewPercantage {
            let id = entry.id

            coredataContext.performAndWait {
                let saveToCoreData = TempTargetsSlider(context: self.coredataContext)
                saveToCoreData.id = id
                saveToCoreData.isPreset = true
                saveToCoreData.enabled = true
                saveToCoreData.hbt = hbt
                saveToCoreData.date = Date()
                saveToCoreData.duration = durationTT as NSDecimalNumber
                do {
                    guard coredataContext.hasChanges else { return }
                    try coredataContext.save()
                } catch {
                    print(error.localizedDescription)
                }
            }
        }
    }

    func enactPreset(id: String) {
        if var preset = presetsTT.first(where: { $0.id == id }) {
            preset.createdAt = Date()
            storage.storeTempTargets([preset])
            showModal(for: nil)

            coredataContext.performAndWait {
                var tempTargetsArray = [TempTargetsSlider]()
                let requestTempTargets = TempTargetsSlider.fetchRequest() as NSFetchRequest<TempTargetsSlider>
                let sortTT = NSSortDescriptor(key: "date", ascending: false)
                requestTempTargets.sortDescriptors = [sortTT]
                try? tempTargetsArray = coredataContext.fetch(requestTempTargets)

                let whichID = tempTargetsArray.first(where: { $0.id == id })

                if whichID != nil {
                    let saveToCoreData = TempTargets(context: self.coredataContext)
                    saveToCoreData.active = true
                    saveToCoreData.date = Date()
                    saveToCoreData.hbt = whichID?.hbt ?? 160
                    // saveToCoreData.id = id
                    saveToCoreData.startDate = Date()
                    saveToCoreData.duration = whichID?.duration ?? 0

                    do {
                        guard coredataContext.hasChanges else { return }
                        try coredataContext.save()
                    } catch {
                        print(error.localizedDescription)
                    }
                } else {
                    let saveToCoreData = TempTargets(context: self.coredataContext)
                    saveToCoreData.active = false
                    saveToCoreData.date = Date()
                    do {
                        guard coredataContext.hasChanges else { return }
                        try coredataContext.save()
                    } catch {
                        print(error.localizedDescription)
                    }
                }
            }
        }
    }

    func removePreset(id: String) {
        presetsTT = presetsTT.filter { $0.id != id }
        storage.storePresets(presetsTT)
    }

    func computeTarget() -> Decimal {
        var ratio = Decimal(percentageTT / 100)
        let c = Decimal(hbt - 100)
        var target = (c / ratio) - c + 100

        if c * (c + target - 100) <= 0 {
            ratio = maxValue
            target = (c / ratio) - c + 100
        }
        return Decimal(Double(target))
    }
}

extension OverrideConfig.StateModel: SettingsObserver {
    func settingsDidChange(_: FreeAPSSettings) {
        units = settingsManager.settings.units
        defaultSmbMinutes = settingsManager.preferences.maxSMBBasalMinutes
        defaultUamMinutes = settingsManager.preferences.maxUAMSMBBasalMinutes
        maxValue = settingsManager.preferences.autosensMax
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

enum IsfAndOrCrOptions: String, CaseIterable {
    case isfAndCr = "ISF/CR"
    case isf = "ISF"
    case cr = "CR"
    case nothing = "None"
}

enum DisableSmbOptions: String, CaseIterable {
    case dontDisable = "Don't Disable"
    case disable = "Disable"
    case disableOnSchedule = "Disable on Schedule"
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

struct RadioButton: View {
    var isSelected: Bool
    var label: String
    var action: () -> Void

    var body: some View {
        Button(action: {
            action()
        }) {
            HStack {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                Text(label) // Add label inside the button to make it tappable
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}
