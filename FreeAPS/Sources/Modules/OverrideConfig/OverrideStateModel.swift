import CoreData
import SwiftUI

extension OverrideConfig {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() var broadcaster: Broadcaster!
        @Injected() var storage: TempTargetsStorage!
        @Injected() var apsManager: APSManager!
        @Injected() var overrideStorage: OverrideStorage!

        @Published var overrideSliderPercentage: Double = 100
        @Published var isEnabled = false
        @Published var indefinite = true
        @Published var overrideDuration: Decimal = 0
        @Published var target: Decimal = 0
        @Published var shouldOverrideTarget: Bool = false
        @Published var smbIsOff: Bool = false
        @Published var id = ""
        @Published var overrideName: String = ""
        @Published var isPreset: Bool = false
        @Published var overridePresets: [OverrideStored] = []
        @Published var advancedSettings: Bool = false
        @Published var isfAndCr: Bool = true
        @Published var isf: Bool = true
        @Published var cr: Bool = true
        @Published var smbIsAlwaysOff: Bool = false
        @Published var start: Decimal = 0
        @Published var end: Decimal = 23
        @Published var smbMinutes: Decimal = 0
        @Published var uamMinutes: Decimal = 0
        @Published var defaultSmbMinutes: Decimal = 0
        @Published var defaultUamMinutes: Decimal = 0
        @Published var selectedTab: Tab = .overrides
        @Published var activeOverrideName: String = ""
        @Published var activeTempTargetName: String = ""
        @Published var currentActiveOverride: OverrideStored?
        @Published var currentActiveTempTarget: TempTargetStored?
        @Published var showOverrideEditSheet = false
        @Published var showTempTargetEditSheet = false
        @Published var showInvalidTargetAlert = false

        var units: GlucoseUnits = .mgdL

        // temp target stuff
        @Published var low: Decimal = 0
        @Published var high: Decimal = 0
        @Published var tempTargetDuration: Decimal = 0
        @Published var tempTargetName: String = ""
        @Published var tempTargetTarget: Decimal = 0 // lel
        @Published var isTempTargetEnabled: Bool = false
        @Published var date = Date()
        @Published var newPresetName = ""
        @Published var tempTargetPresets: [TempTargetStored] = []
        @Published var percentageTT = 100.0
        @Published var maxValue: Decimal = 1.2
        @Published var viewPercantage = false
        @Published var hbt: Double = 160
        @Published var didSaveSettings: Bool = false

        let coredataContext = CoreDataStack.shared.newTaskContext()
        let viewContext = CoreDataStack.shared.persistentContainer.viewContext

        var alertMessage: String {
            let target: String = units == .mgdL ? "70-270 mg/dl" : "4-15 mmol/l"
            return "Please enter a valid target between" + " \(target)."
        }

        override func subscribe() {
            // TODO: - execute the init concurrently
            setupNotification()
            units = settingsManager.settings.units
            defaultSmbMinutes = settingsManager.preferences.maxSMBBasalMinutes
            defaultUamMinutes = settingsManager.preferences.maxUAMSMBBasalMinutes
            setupOverridePresetsArray()
            setupTempTargetPresetsArray()
            updateLatestOverrideConfiguration()
            updateLatestTempTargetConfiguration()
            maxValue = settingsManager.preferences.autosensMax
            broadcaster.register(SettingsObserver.self, observer: self)
        }

        func isInputInvalid(target: Decimal) -> Bool {
            guard target != 0 else { return false }

            if units == .mgdL,
               target < 70 || target > 270
            {
                showInvalidTargetAlert = true
                return true
            } else if units == .mmolL,
                      target < 4 || target > 15
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
        Foundation.NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleOverrideConfigurationUpdate),
            name: .didUpdateOverrideConfiguration,
            object: nil
        )
    }

    @objc private func handleOverrideConfigurationUpdate() {
        updateLatestOverrideConfiguration()
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
            let id = await loadLatestTempTargetConfigurations(fetchLimit: 1)
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
            }
        } catch {
            debugPrint(
                "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to set active preset name with error: \(error.localizedDescription)"
            )
        }
    }

    // Fill the array of the Override Presets to display them in the UI
    private func setupTempTargetPresetsArray() {
        Task {
            let ids = await self.fetchForTempTargetPresets()
            await updateTempTargetPresetsArray(with: ids)
        }
    }

    /// Returns the NSManagedObjectID of the Temp Target Presets
    func fetchForTempTargetPresets() async -> [NSManagedObjectID] {
        let results = await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: TempTargetStored.self,
            onContext: coredataContext,
            predicate: NSPredicate.allTempTargetPresets,
            key: "date",
            ascending: true
        )

        guard let fetchedResults = results as? [TempTargetStored] else { return [] }

        return await coredataContext.perform {
            return fetchedResults.map(\.objectID)
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

    // Creates and enacts a non Preset Temp Target
    func saveCustomTempTarget() async {
        let newTempTarget = TempTargetStored(context: coredataContext)
        newTempTarget.date = Date()
        newTempTarget.id = UUID()
        newTempTarget.enabled = true
        newTempTarget.duration = tempTargetDuration as NSDecimalNumber
        newTempTarget.isUploadedToNS = false
        newTempTarget.name = tempTargetName
        newTempTarget.target = tempTargetTarget as NSDecimalNumber
        newTempTarget.isPreset = false

        // disable all TempTargets
        await disableAllActiveOverrides(createOverrideRunEntry: true)

        // Save Temp Target to Core Data
        do {
            guard coredataContext.hasChanges else { return }
            try coredataContext.save()
        } catch let error as NSError {
            debugPrint(
                "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to save TempTarget to Core Data with error: \(error.userInfo)"
            )
        }

        // Reset State variables
        await resetTempTargetState()

        // Update View
        updateLatestTempTargetConfiguration()
    }

    // Creates a new Temp Target Preset
    func saveTempTargetPreset() async {
        let newTempTarget = TempTargetStored(context: coredataContext)
        newTempTarget.date = Date()
        newTempTarget.id = UUID()
        newTempTarget.enabled = false
        newTempTarget.duration = tempTargetDuration as NSDecimalNumber
        newTempTarget.isUploadedToNS = false
        newTempTarget.name = tempTargetName
        newTempTarget.target = tempTargetTarget as NSDecimalNumber
        newTempTarget.isPreset = true

        // Save Temp Target to Core Data
        do {
            guard coredataContext.hasChanges else { return }
            try coredataContext.save()
        } catch let error as NSError {
            debugPrint(
                "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to save TempTarget to Core Data with error: \(error.userInfo)"
            )
        }

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
            await disableAllActiveTempTargets(except: id, createTempTargetRunEntry: currentActiveTempTarget != nil)

            /// reset state variables
            await resetTempTargetState()

            guard viewContext.hasChanges else { return }
            try viewContext.save()

            // Update View
            updateLatestTempTargetConfiguration()
        } catch {
            debugPrint("\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to enact Override Preset")
        }
    }

    // Disable all active Temp Targets

    func loadLatestTempTargetConfigurations(fetchLimit: Int) async -> [NSManagedObjectID] {
        let results = await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: TempTargetStored.self,
            onContext: coredataContext,
            predicate: NSPredicate.lastActiveTempTarget,
            key: "date",
            ascending: true,
            fetchLimit: fetchLimit
        )

        guard let fetchedResults = results as? [TempTargetStored] else { return [] }

        return await coredataContext.perform {
            return fetchedResults.map(\.objectID)
        }
    }

    @MainActor func disableAllActiveTempTargets(except id: NSManagedObjectID? = nil, createTempTargetRunEntry: Bool) async {
        // Get ALL NSManagedObject IDs of ALL active Temp Targets to cancel every single Temp Target
        let ids = await loadLatestTempTargetConfigurations(fetchLimit: 0) // 0 = no fetch limit

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

                    // Update the View
                    self.updateLatestTempTargetConfiguration()
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
        let duplidateId = await copyRunningTempTarget(tempTargetPresetToDuplicate)

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

    // Copy the current Temp Target if it is a RUNNING Preset
    /// otherwise we would edit the Preset
    @MainActor func copyRunningTempTarget(_ tempTarget: TempTargetStored) async -> NSManagedObjectID {
        let newTempTarget = TempTargetStored(context: viewContext)
        newTempTarget.date = tempTarget.date
        newTempTarget.id = tempTarget.id
        newTempTarget.enabled = tempTarget.enabled
        newTempTarget.duration = tempTarget.duration
        newTempTarget.isUploadedToNS = true // to avoid getting duplicates on NS
        newTempTarget.name = tempTarget.name
        newTempTarget.target = tempTarget.target
        newTempTarget.isPreset = false // no Preset

        await viewContext.perform {
            do {
                guard self.viewContext.hasChanges else { return }
                try self.viewContext.save()
            } catch let error as NSError {
                debugPrint(
                    "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to copy Temp Target with error: \(error.userInfo)"
                )
            }
        }

        return newTempTarget.objectID
    }

    // Deletion of Temp Targets
    func invokeTempTargetPresetDeletion(_ objectID: NSManagedObjectID) async {
        await deleteOverridePreset(objectID)

        // Update Presets View
        setupTempTargetPresetsArray()
    }

    @MainActor func deleteOverridePreset(_ objectID: NSManagedObjectID) async {
        await CoreDataStack.shared.deleteObject(identifiedBy: objectID)
    }

    @MainActor func resetTempTargetState() async {
        tempTargetName = ""
        tempTargetTarget = 0
        tempTargetDuration = 0
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
