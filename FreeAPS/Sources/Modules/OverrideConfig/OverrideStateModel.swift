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
        var showTempTargetEditSheet = false
        var currentActiveTempTarget: TempTargetStored?
        var currentActiveOverride: OverrideStored?
        var activeTempTargetName: String = ""

        var units: GlucoseUnits = .mgdL

        // temp target stuff
        var tempTargetDuration: Decimal = 0
        var tempTargetName: String = ""
        var tempTargetTarget: Decimal = 0 // lel
        var isTempTargetEnabled: Bool = false
        var date = Date()
        var newPresetName = ""
        var tempTargetPresets: [TempTargetStored] = []
        var percentage = 100.0
        var maxValue: Decimal = 1.2
        var minValue: Decimal = 0.15
        var viewPercantage = false
        var halfBasalTarget: Decimal = 160
        var settingHalfBasalTarget: Decimal = 160
        var didSaveSettings: Bool = false
        var didAdjustSens: Bool = false {
            didSet {
                handleAdjustSensToggle()
            }
        }

        let coredataContext = CoreDataStack.shared.newTaskContext()
        let viewContext = CoreDataStack.shared.persistentContainer.viewContext

        var alertMessage: String {
            let target: String = units == .mgdL ? "70-270 mg/dl" : "4-15 mmol/l"
            return "Please enter a valid target between" + " \(target)."
        }

        private var cancellables = Set<AnyCancellable>()

        override func subscribe() {
            setupNotification()
            setupSettings()
            broadcaster.register(SettingsObserver.self, observer: self)

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

        private func setupSettings() {
            units = settingsManager.settings.units
            defaultSmbMinutes = settingsManager.preferences.maxSMBBasalMinutes
            defaultUamMinutes = settingsManager.preferences.maxUAMSMBBasalMinutes
            maxValue = settingsManager.preferences.autosensMax
            minValue = settingsManager.preferences.autosensMin
            settingHalfBasalTarget = settingsManager.preferences.halfBasalExerciseTarget
            halfBasalTarget = settingsManager.preferences.halfBasalExerciseTarget
            percentage = Double(computeAdjustedPercentage() * 100)
        }

        func isInputInvalid(target: Decimal) -> Bool {
            guard target != 0 else { return false }

            if units == .mgdL,
               target < 80 || target > 270 // in oref min lowTT = 80!
            {
                showInvalidTargetAlert = true
                return true
            } else if units == .mmolL,
                      target < 4.4 || target > 15 // in oref min lowTT = 80!
            {
                showInvalidTargetAlert = true
                return true
            } else {
                return false
            }
        }
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

        // Custom Notification to update View when an Temp Target has been cancelled via Home View
        Foundation.NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleTempTargetConfigurationUpdate),
            name: .didUpdateTempTargetConfiguration,
            object: nil
        )
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
            percentage: overrideSliderPercentage,
            smbIsOff: smbIsOff,
            isPreset: isPreset,
            id: id,
            overrideTarget: shouldOverrideTarget,
            target: target,
            advancedSettings: advancedSettings,
            isfAndCr: isfAndCr,
            isf: isf,
            cr: cr,
            smbIsAlwaysOff: smbIsAlwaysOff,
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
            percentage: overrideSliderPercentage,
            smbIsOff: smbIsOff,
            isPreset: true,
            id: id,
            overrideTarget: shouldOverrideTarget,
            target: target,
            advancedSettings: advancedSettings,
            isfAndCr: isfAndCr,
            isf: isf,
            cr: cr,
            smbIsAlwaysOff: smbIsAlwaysOff,
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
        overrideSliderPercentage = 100

        advancedSettings = false
        smbIsOff = false
        overrideName = ""
        shouldOverrideTarget = false
        isf = true
        cr = true
        isfAndCr = true
        smbIsAlwaysOff = false
        start = 0
        end = 23
        smbMinutes = defaultSmbMinutes
        uamMinutes = defaultUamMinutes
        target = 0
    }
}

// MARK: - Temp Targets

extension OverrideConfig.StateModel {
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

    // Fill the array of the Temp Target Presets to display them in the UI
    private func setupTempTargetPresetsArray() {
        Task {
            let ids = await tempTargetStorage.fetchForTempTargetPresets()
            await updateTempTargetPresetsArray(with: ids)
        }
    }

    @MainActor private func updateTempTargetPresetsArray(with IDs: [NSManagedObjectID]) async {
        do {
            let tempTargetObjects = try IDs.compactMap { id in
                try viewContext.existingObject(with: id) as? TempTargetStored
            }
            tempTargetPresets = tempTargetObjects
        } catch {
            debugPrint(
                "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to extract Temp Targets as NSManagedObjects from the NSManagedObjectIDs with error: \(error.localizedDescription)"
            )
        }
    }

    func saveTempTargetToStorage(tempTargets: [TempTarget]) {
        tempTargetStorage.saveTempTargetsToStorage(tempTargets)
    }

    // Creates and enacts a non Preset Temp Target
    func saveCustomTempTarget() async {
        // First disable all active TempTargets
        await disableAllActiveTempTargets(createTempTargetRunEntry: true)

        let tempTarget = TempTarget(
            name: tempTargetName,
            createdAt: Date(),
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

        // Enact Temp Target for oref
        tempTargetStorage.saveTempTargetsToStorage([tempTarget])

        // Reset State variables
        await resetTempTargetState()

        // Update View
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

    // Enact Temp Target Preset
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
        tempTargetTarget = 0
        tempTargetDuration = 0
        percentage = 100
        halfBasalTarget = settingsManager.preferences.halfBasalExerciseTarget
    }

    func handleAdjustSensToggle() {
        if !didAdjustSens {
            halfBasalTarget = settingHalfBasalTarget
            percentage = Double(computeAdjustedPercentage(using: settingHalfBasalTarget) * 100)
        }
    }

    func computeHalfBasalTarget() -> Double {
        let adjustmentRatio = Decimal(percentage / 100)
        let normalTarget: Decimal = 100
        let tempTargetValue: Decimal = tempTargetTarget
        var halfBasalTargetValue = halfBasalTarget
        if adjustmentRatio != 1 {
            halfBasalTargetValue = ((2 * adjustmentRatio * normalTarget) - normalTarget - (adjustmentRatio * tempTargetValue)) /
                (adjustmentRatio - 1)
        }
        return round(Double(halfBasalTargetValue))
    }

    func computeSliderLow() -> Double {
        var minSens: Double = 15
        let tempTargetValue = tempTargetTarget
        if tempTargetValue == 0 { return minSens }
        if tempTargetValue < 100 ||
            (
                !settingsManager.preferences.highTemptargetRaisesSensitivity && !settingsManager.preferences
                    .exerciseMode
            ) { minSens = 100 }
        minSens = max(0, minSens)
        return minSens
    }

    func computeSliderHigh() -> Double {
        var maxSens = Double(maxValue * 100)
        let tempTargetValue = tempTargetTarget
        if tempTargetValue == 0 { return maxSens }
        if tempTargetValue > 100 || !settingsManager.preferences.lowTemptargetLowersSensitivity { maxSens = 100 }
        return maxSens
    }

    func computeAdjustedPercentage(using initialHalfBasalTarget: Decimal? = nil) -> Decimal {
        let halfBasalTargetValue = initialHalfBasalTarget ?? halfBasalTarget
        let normalTarget: Decimal = 100
        let deviationFromNormal = (halfBasalTargetValue - normalTarget)
        let tempTargetValue = tempTargetTarget
        var adjustmentRatio: Decimal = 1

        if deviationFromNormal * (deviationFromNormal + tempTargetValue - normalTarget) <= 0 {
            adjustmentRatio = maxValue
        } else {
            adjustmentRatio = deviationFromNormal / (deviationFromNormal + tempTargetValue - normalTarget)
        }

        adjustmentRatio = min(adjustmentRatio, maxValue)
        return adjustmentRatio
    }
}

extension OverrideConfig.StateModel: SettingsObserver {
    func settingsDidChange(_: FreeAPSSettings) {
        units = settingsManager.settings.units
        defaultSmbMinutes = settingsManager.preferences.maxSMBBasalMinutes
        defaultUamMinutes = settingsManager.preferences.maxUAMSMBBasalMinutes
        maxValue = settingsManager.preferences.autosensMax
        minValue = settingsManager.preferences.autosensMin
    }
}
