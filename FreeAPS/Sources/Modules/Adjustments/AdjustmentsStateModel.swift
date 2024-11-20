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
    }

    @objc private func handleOverrideConfigurationUpdate() {
        updateLatestOverrideConfiguration()
        Foundation.NotificationCenter.default.publisher(for: .willUpdateOverrideConfiguration)
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.updateLatestOverrideConfiguration()
            }
            .store(in: &cancellables)
    }

    @objc private func handleTempTargetConfigurationUpdate() {
        updateLatestTempTargetConfiguration()
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

        // Then save and activate a new custom Override
        await overrideStorage.storeOverride(override: override)

        // Reset State variables
        await resetStateVariables()

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
        target = currentGlucoseTarget
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

// MARK: - Temp Targets

extension Adjustments.StateModel {
    // MARK: - Setup the State variables with the last Temp Target configuration

    /// First get the latest Temp Target corresponding NSManagedObjectID with a background fetch
    /// Then unpack it on the view context and update the State variables which can be used on in the View for some Logic
    /// This also needs to be called when we cancel an Temp Target via the Home View to update the State of the Button for this case
    func updateLatestTempTargetConfiguration() {
        Task {
            let id = await tempTargetStorage.loadLatestTempTargetConfigurations(fetchLimit: 1)
            async let updateState: () = updateLatestTempTargetConfigurationOfState(from: id)
            async let setTempTarget: () = setCurrentTempTarget(from: id)

            _ = await (updateState, setTempTarget)
        }
    }

    @MainActor func updateLatestTempTargetConfigurationOfState(from IDs: [NSManagedObjectID]) async {
        do {
            let result = try IDs.compactMap { id in
                try viewContext.existingObject(with: id) as? TempTargetStored
            }
            isTempTargetEnabled = result.first?.enabled ?? false

            if !isEnabled {
                await resetTempTargetState()
            }
        } catch {
            debugPrint(
                "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to update latest temp target configuration"
            )
        }
    }

    // Sets the current active Preset name to show in the UI
    @MainActor func setCurrentTempTarget(from IDs: [NSManagedObjectID]) async {
        do {
            guard let firstID = IDs.first else {
                activeTempTargetName = "Custom Temp Target"
                currentActiveTempTarget = nil
                return
            }

            if let tempTargetToEdit = try viewContext.existingObject(with: firstID) as? TempTargetStored {
                currentActiveTempTarget = tempTargetToEdit
                activeTempTargetName = tempTargetToEdit.name ?? "Custom Temp Target"
                tempTargetTarget = tempTargetToEdit.target?.decimalValue ?? 0
            }
        } catch {
            debugPrint(
                "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to set active preset name with error: \(error.localizedDescription)"
            )
        }
    }

    private func setupTempTargets(
        fetchFunction: @escaping () async -> [NSManagedObjectID],
        updateFunction: @escaping @MainActor([TempTargetStored]) -> Void
    ) {
        Task {
            let ids = await fetchFunction()
            let tempTargetObjects = await fetchTempTargetObjects(for: ids)
            await updateFunction(tempTargetObjects)
        }
    }

    @MainActor private func fetchTempTargetObjects(for IDs: [NSManagedObjectID]) async -> [TempTargetStored] {
        do {
            return try IDs.compactMap { id in
                try viewContext.existingObject(with: id) as? TempTargetStored
            }
        } catch {
            debugPrint(
                "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to extract Temp Targets as NSManagedObjects from the NSManagedObjectIDs with error: \(error.localizedDescription)"
            )
            return []
        }
    }

    private func setupTempTargetPresetsArray() {
        setupTempTargets(
            fetchFunction: tempTargetStorage.fetchForTempTargetPresets,
            updateFunction: { tempTargets in
                self.tempTargetPresets = tempTargets
            }
        )
    }

    private func setupScheduledTempTargetsArray() {
        setupTempTargets(
            fetchFunction: tempTargetStorage.fetchScheduledTempTargets,
            updateFunction: { tempTargets in
                self.scheduledTempTargets = tempTargets
            }
        )
    }

    func saveTempTargetToStorage(tempTargets: [TempTarget]) {
        tempTargetStorage.saveTempTargetsToStorage(tempTargets)
    }

    func invokeSaveOfCustomTempTargets() async {
        if date > Date() {
            await saveScheduledTempTarget()
        } else {
            await saveCustomTempTarget()
        }
    }

    // Save scheduled Preset to Core Data
    func saveScheduledTempTarget() async {
        // Save date to a constant to allow multiple executions of this function at the same time, i.e. allowing for scheduling multiple TTs
        let date = self.date

        guard date > Date() else { return }

        let tempTarget = TempTarget(
            name: tempTargetName,
            createdAt: date,
            targetTop: tempTargetTarget,
            targetBottom: tempTargetTarget,
            duration: tempTargetDuration,
            enteredBy: TempTarget.manual,
            reason: TempTarget.custom,
            isPreset: false,
            enabled: false,
            halfBasalTarget: halfBasalTarget
        )

        await tempTargetStorage.storeTempTarget(tempTarget: tempTarget)

        // Update Scheduled Temp Targets Array
        setupScheduledTempTargetsArray()

        // If the scheduled date equals Date() enable the Preset
        Task {
            // First wait until the time has passed
            await waitUntilDate(date)
            // Then disable previous Temp Targets
            await disableAllActiveTempTargets(createTempTargetRunEntry: true)
            // Set 'enabled' property to true, i.e. enacting it in Core Data
            await enableScheduledTempTarget(for: date)
            // Activate the scheduled TT also for oref
            tempTargetStorage.saveTempTargetsToStorage([tempTarget])
        }
    }

    private func enableScheduledTempTarget(for date: Date) async {
        let ids = await tempTargetStorage.fetchScheduledTempTarget(for: date)

        guard let firstID = ids.first else {
            debugPrint("No Temp Target found for the specified date.")
            return
        }

        await setCurrentTempTarget(from: ids)

        await MainActor.run {
            do {
                if let tempTarget = try viewContext.existingObject(with: firstID) as? TempTargetStored {
                    tempTarget.enabled = true
                    try viewContext.save()

                    // Update Buttons in Adjustments View
                    isTempTargetEnabled = true
                }
            } catch {
                debugPrint("Failed to enable the Temp Target for the specified date: \(error.localizedDescription)")
            }
        }

        // Refresh the list of scheduled Temp Targets
        setupScheduledTempTargetsArray()
    }

    private func waitUntilDate(_ targetDate: Date) async {
        while Date() < targetDate {
            let timeInterval = targetDate.timeIntervalSince(Date())
            let sleepDuration = min(timeInterval, 60.0) // check every 60s
            try? await Task.sleep(nanoseconds: UInt64(sleepDuration * 1_000_000_000))
        }
    }

    // Creates and enacts a non Preset Temp Target
    func saveCustomTempTarget() async {
        // First disable all active TempTargets
        await disableAllActiveTempTargets(createTempTargetRunEntry: true)

        let tempTarget = TempTarget(
            name: tempTargetName,
            createdAt: date,
            targetTop: tempTargetTarget,
            targetBottom: tempTargetTarget,
            duration: tempTargetDuration,
            enteredBy: TempTarget.manual,
            reason: TempTarget.custom,
            isPreset: false,
            enabled: true,
            halfBasalTarget: halfBasalTarget
        )

        // Save Temp Target to Core Data
        await tempTargetStorage.storeTempTarget(tempTarget: tempTarget)

        // Start Temp Target for oref
        tempTargetStorage.saveTempTargetsToStorage([tempTarget])

        // Reset State variables
        await resetTempTargetState()

        // Update View
        isTempTargetEnabled = true
        updateLatestTempTargetConfiguration()
    }

    // Creates a new Temp Target Preset
    func saveTempTargetPreset() async {
        let tempTarget = TempTarget(
            name: tempTargetName,
            createdAt: Date(),
            targetTop: tempTargetTarget,
            targetBottom: tempTargetTarget,
            duration: tempTargetDuration,
            enteredBy: TempTarget.manual,
            reason: TempTarget.custom,
            isPreset: true,
            enabled: false,
            halfBasalTarget: halfBasalTarget
        )

        // Save to Core Data
        await tempTargetStorage.storeTempTarget(tempTarget: tempTarget)

        // Reset State variables
        await resetTempTargetState()

        // Update View
        setupTempTargetPresetsArray()
    }

    // Start Temp Target Preset
    /// here we only have to update the Boolean Flag 'enabled'
    @MainActor func enactTempTargetPreset(withID id: NSManagedObjectID) async {
        do {
            /// get the underlying NSManagedObject of the Override that should be enabled
            let tempTargetToEnact = try viewContext.existingObject(with: id) as? TempTargetStored
            tempTargetToEnact?.enabled = true
            tempTargetToEnact?.date = Date()
            tempTargetToEnact?.isUploadedToNS = false

            /// Update the 'Cancel Temp Target' button state
            isTempTargetEnabled = true

            /// disable all active Temp Targets and reset state variables
            async let disableTempTargets: () = disableAllActiveTempTargets(
                except: id,
                createTempTargetRunEntry: currentActiveTempTarget != nil
            )
            async let resetState: () = resetTempTargetState()

            _ = await (disableTempTargets, resetState)

            if viewContext.hasChanges {
                try viewContext.save()
            }

            // Update View
            updateLatestTempTargetConfiguration()

            // Map to TempTarget Struct
            let tempTarget = TempTarget(
                name: tempTargetToEnact?.name,
                createdAt: Date(),
                targetTop: tempTargetToEnact?.target?.decimalValue,
                targetBottom: tempTargetToEnact?.target?.decimalValue,
                duration: tempTargetToEnact?.duration?.decimalValue ?? 0,
                enteredBy: TempTarget.manual,
                reason: TempTarget.custom,
                isPreset: true,
                enabled: true,
                halfBasalTarget: halfBasalTarget
            )

            // Make sure the Temp Target gets used by Oref
            tempTargetStorage.saveTempTargetsToStorage([tempTarget])
        } catch {
            debugPrint("\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to enact Override Preset")
        }
    }

    // Disable all active Temp Targets
    @MainActor func disableAllActiveTempTargets(except id: NSManagedObjectID? = nil, createTempTargetRunEntry: Bool) async {
        // Get ALL NSManagedObject IDs of ALL active Temp Targets to cancel every single Temp Target
        let ids = await tempTargetStorage.loadLatestTempTargetConfigurations(fetchLimit: 0) // 0 = no fetch limit

        await viewContext.perform {
            do {
                // Fetch the existing TempTargetStored objects from the context
                let results = try ids.compactMap { id in
                    try self.viewContext.existingObject(with: id) as? TempTargetStored
                }

                // If there are no results, return early
                guard !results.isEmpty else { return }

                // Check if we also need to create a corresponding TempTargetRunStored entry, i.e. when the User uses the Cancel Button in Temp Target View
                if createTempTargetRunEntry {
                    // Use the first temp target to create a new TempTargetRunStored entry
                    if let canceledTempTarget = results.first {
                        let newTempTargetRunStored = TempTargetRunStored(context: self.viewContext)
                        newTempTargetRunStored.id = UUID()
                        newTempTargetRunStored.name = canceledTempTarget.name
                        newTempTargetRunStored.startDate = canceledTempTarget.date ?? .distantPast
                        newTempTargetRunStored.endDate = Date()
                        newTempTargetRunStored
                            .target = canceledTempTarget.target ?? 0
                        newTempTargetRunStored.tempTarget = canceledTempTarget
                        newTempTargetRunStored.isUploadedToNS = false
                    }
                }

                // Disable all override except the one with overrideID
                for tempTargetToCancel in results {
                    if tempTargetToCancel.objectID != id {
                        tempTargetToCancel.enabled = false
                    }
                }

                // Save the context if there are changes
                if self.viewContext.hasChanges {
                    try self.viewContext.save()

                    // Update the storage
                    self.tempTargetStorage.saveTempTargetsToStorage([TempTarget.cancel(at: Date().addingTimeInterval(-1))])
                }
            } catch {
                debugPrint(
                    "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to disable active Overrides with error: \(error.localizedDescription)"
                )
            }
        }
    }

    @MainActor func duplicateTempTargetPresetAndCancelPreviousTempTarget() async {
        // We get the current active Preset by using currentActiveTempTarget which can either be a Preset or a custom Override
        guard let tempTargetPresetToDuplicate = currentActiveTempTarget,
              tempTargetPresetToDuplicate.isPreset == true else { return }

        // Copy the current TempTarget-Preset to not edit the underlying Preset
        let duplidateId = await tempTargetStorage.copyRunningTempTarget(tempTargetPresetToDuplicate)

        // Cancel the duplicated Temp Target
        /// As we are on the Main Thread already we don't need to cancel via the objectID in this case
        do {
            try await viewContext.perform {
                tempTargetPresetToDuplicate.enabled = false

                guard self.viewContext.hasChanges else { return }
                try self.viewContext.save()
            }

            if let tempTargetToEdit = try viewContext.existingObject(with: duplidateId) as? TempTargetStored
            {
                currentActiveTempTarget = tempTargetToEdit
                activeTempTargetName = tempTargetToEdit.name ?? "Custom Temp Target"
            }
        } catch {
            debugPrint(
                "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to cancel previous override with error: \(error.localizedDescription)"
            )
        }
    }

    // Deletion of Temp Targets
    func invokeTempTargetPresetDeletion(_ objectID: NSManagedObjectID) async {
        await tempTargetStorage.deleteOverridePreset(objectID)

        // Update Presets View
        setupTempTargetPresetsArray()
    }

    @MainActor func resetTempTargetState() async {
        tempTargetName = ""
        tempTargetTarget = 100
        tempTargetDuration = 0
        percentage = 100
        halfBasalTarget = settingHalfBasalTarget
    }

    func computeHalfBasalTarget(
        usingTarget initialTarget: Decimal? = nil,
        usingPercentage initialPercentage: Double? = nil
    ) -> Double {
        let adjustmentPercentage = initialPercentage ?? percentage
        let adjustmentRatio = Decimal(adjustmentPercentage / 100)
        let tempTargetValue: Decimal = initialTarget ?? tempTargetTarget
        var halfBasalTargetValue = halfBasalTarget
        if adjustmentRatio != 1 {
            halfBasalTargetValue = ((2 * adjustmentRatio * normalTarget) - normalTarget - (adjustmentRatio * tempTargetValue)) /
                (adjustmentRatio - 1)
        }
        return round(Double(halfBasalTargetValue))
    }

    func isAdjustSensEnabled(usingTarget initialTarget: Decimal? = nil) -> Bool {
        let target = initialTarget ?? tempTargetTarget
        if target < normalTarget, lowTTlowersSens { return true }
        if target > normalTarget, highTTraisesSens || isExerciseModeActive { return true }
        return false
    }

    func computeSliderLow(usingTarget initialTarget: Decimal? = nil) -> Double {
        let calcTarget = initialTarget ?? tempTargetTarget
        guard calcTarget != 0 else { return 15 } // oref defined maximum sensitivity
        let minSens = calcTarget < normalTarget ? 105 : 15
        return Double(max(0, minSens))
    }

    func computeSliderHigh(usingTarget initialTarget: Decimal? = nil) -> Double {
        let calcTarget = initialTarget ?? tempTargetTarget
        guard calcTarget != 0 else { return Double(maxValue * 100) } // oref defined limit for increased insulin delivery
        let maxSens = calcTarget > normalTarget ? 95 : Double(maxValue * 100)
        return maxSens
    }

    func computeAdjustedPercentage(
        usingHBT initialHalfBasalTarget: Decimal? = nil,
        usingTarget initialTarget: Decimal? = nil
    ) -> Double {
        let halfBasalTargetValue = initialHalfBasalTarget ?? halfBasalTarget
        let calcTarget = initialTarget ?? tempTargetTarget
        let deviationFromNormal = halfBasalTargetValue - normalTarget

        let adjustmentFactor = deviationFromNormal + (calcTarget - normalTarget)
        let adjustmentRatio: Decimal = (deviationFromNormal * adjustmentFactor <= 0) ? maxValue : deviationFromNormal /
            adjustmentFactor

        return Double(min(adjustmentRatio, maxValue) * 100).rounded()
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

enum TempTargetSensitivityAdjustmentType: String, CaseIterable {
    case standard = "Standard"
    case slider = "Custom"
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

struct TargetPicker: View {
    let label: String
    @Binding var selection: Decimal
    let options: [Decimal]
    let units: GlucoseUnits
    var hasChanges: Binding<Bool>?
    @Binding var targetStep: Decimal
    @Binding var displayPickerTarget: Bool
    var toggleScrollWheel: (_ picker: Bool) -> Bool

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(
                (units == .mgdL ? selection.description : selection.formattedAsMmolL) + " " + units.rawValue
            )
            .foregroundColor(!displayPickerTarget ? .primary : .accentColor)
        }
        .onTapGesture {
            displayPickerTarget = toggleScrollWheel(displayPickerTarget)
        }
        if displayPickerTarget {
            HStack {
                // Radio buttons and text on the left side
                VStack(alignment: .leading) {
                    // Radio buttons for step iteration
                    let stepChoices: [Decimal] = units == .mgdL ? [1, 5] : [1, 9]
                    ForEach(stepChoices, id: \.self) { step in
                        let label = (units == .mgdL ? step.description : step.formattedAsMmolL) + " " +
                            units.rawValue
                        RadioButton(
                            isSelected: targetStep == step,
                            label: label
                        ) {
                            targetStep = step
                            selection = Adjustments.StateModel.roundTargetToStep(selection, step)
                        }
                        .padding(.top, 10)
                    }
                }
                .frame(maxWidth: .infinity)

                Spacer()

                // Picker on the right side
                Picker(selection: Binding(
                    get: { Adjustments.StateModel.roundTargetToStep(selection, targetStep) },
                    set: {
                        selection = $0
                        hasChanges?.wrappedValue = true // This safely updates if hasChanges is provided
                    }
                ), label: Text("")) {
                    ForEach(options, id: \.self) { option in
                        Text((units == .mgdL ? option.description : option.formattedAsMmolL) + " " + units.rawValue)
                            .tag(option)
                    }
                }
                .pickerStyle(WheelPickerStyle())
                .frame(maxWidth: .infinity)
            }
            .listRowSeparator(.hidden, edges: .top)
        }
    }
}
