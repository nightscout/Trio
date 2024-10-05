import CoreData
import SwiftUI

extension OverrideConfig {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() var broadcaster: Broadcaster!
        @Injected() var storage: TempTargetsStorage!
        @Injected() var apsManager: APSManager!
        @Injected() var overrideStorage: OverrideStorage!

        @Published var overridePercentage: Double = 100
        @Published var isEnabled = false
        @Published var indefinite = true
        @Published var overrideDuration: Decimal = 0
        @Published var target: Decimal = 100
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
        @Published var smbIsScheduledOff: Bool = false
        @Published var start: Decimal = 0
        @Published var end: Decimal = 0
        @Published var smbMinutes: Decimal = 0
        @Published var uamMinutes: Decimal = 0
        @Published var defaultSmbMinutes: Decimal = 0
        @Published var defaultUamMinutes: Decimal = 0
        @Published var selectedTab: Tab = .overrides
        @Published var activeOverrideName: String = ""
        @Published var currentActiveOverride: OverrideStored?
        @Published var showOverrideEditSheet = false

        var units: GlucoseUnits = .mgdL

        // temp target stuff
        @Published var low: Decimal = 0
        @Published var high: Decimal = 0
        @Published var durationTT: Decimal = 0
        @Published var date = Date()
        @Published var newPresetName = ""
        @Published var presetsTT: [TempTarget] = []
        @Published var percentageTT = 100.0
        @Published var maxValue: Decimal = 1.2
        @Published var viewPercantage = false
        @Published var hbt: Double = 160
        @Published var didSaveSettings: Bool = false

        var alertMessage: String {
            let target: String = units == .mgdL ? "70-270 mg/dl" : "4-15 mmol/l"
            return "Please enter a valid target between" + " \(target)."
        }

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
