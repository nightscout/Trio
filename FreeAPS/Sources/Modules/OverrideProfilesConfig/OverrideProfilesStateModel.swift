import CoreData
import SwiftUI

extension OverrideProfilesConfig {
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
        @Published var currentActiveOverride: OverrideStored?
        @Published var showOverrideEditSheet = false
        @Published var showInvalidTargetAlert = false

        var units: GlucoseUnits = .mmolL

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

        func isInputInvalid(target: Decimal) -> Bool {
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

extension OverrideProfilesConfig.StateModel {
    /// listens for the notifications sent when the managedObjectContext has saved!
    func setupNotification() {
        Foundation.NotificationCenter.default.addObserver(
            self,
            selector: #selector(contextDidSave(_:)),
            name: Notification.Name.NSManagedObjectContextDidSave,
            object: nil
        )

        /// listens for notifications sent when a Preset was added
        Foundation.NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePresetsUpdate),
            name: .didUpdateOverridePresets,
            object: nil
        )
    }

    @objc private func handlePresetsUpdate() {
        setupOverridePresetsArray()
    }

    /// determine the actions when the context has changed
    /// its done on a background thread and after that the UI gets updated on the main thread
    @objc private func contextDidSave(_ notification: Notification) {
        guard let userInfo = notification.userInfo else { return }

        Task { [weak self] in
            await self?.processUpdates(userInfo: userInfo)
        }
    }

    private func processUpdates(userInfo: [AnyHashable: Any]) async {
        var objects = Set((userInfo[NSInsertedObjectsKey] as? Set<NSManagedObject>) ?? [])
        objects.formUnion((userInfo[NSUpdatedObjectsKey] as? Set<NSManagedObject>) ?? [])
        objects.formUnion((userInfo[NSDeletedObjectsKey] as? Set<NSManagedObject>) ?? [])

        let overrideUpdates = objects.filter { $0 is OverrideStored }

        DispatchQueue.global(qos: .background).async {
            if overrideUpdates.isNotEmpty {
                self.updateLatestOverrideConfiguration()
            }
        }
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

            /// Update the 'Cancel Override' button state
            isEnabled = true

            /// disable all active Overrides and reset state variables
            /// do not create a OverrideRunEntry because we only want that if we cancel a running Override, not when enacting a Preset
            await disableAllActiveOverrides(except: id, createOverrideRunEntry: false)

            await resetStateVariables()

            guard viewContext.hasChanges else { return }
            try viewContext.save()
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
                        newOverrideRunStored.startDate = canceledOverride.date ?? .distantPast
                        newOverrideRunStored.endDate = Date()
                        newOverrideRunStored
                            .target = NSDecimalNumber(decimal: self.overrideStorage.calculateTarget(override: canceledOverride))
                        newOverrideRunStored.override = canceledOverride
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

        await overrideStorage.storeOverride(override: override)
        await resetStateVariables()
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

        await overrideStorage.storeOverride(override: preset)

        // Custom Notification to update Presets View
        Foundation.NotificationCenter.default.post(name: .didUpdateOverridePresets, object: nil)

        // Prevent showing the current config of the recently added Preset
        await resetStateVariables()
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
        // Custom Notification to update Presets View
        Foundation.NotificationCenter.default.post(name: .didUpdateOverridePresets, object: nil)
    }

    // MARK: - Setup the State variables with the last Override configuration

    /// First get the latest Overrides corresponding NSManagedObjectID with a background fetch
    /// Then unpack it on the view context and update the State variables which can be used on in the View for some Logic
    /// This also needs to be called when we cancel an Override via the Home View to update the State of the Button for this case
    func updateLatestOverrideConfiguration() {
        Task {
            let id = await overrideStorage.loadLatestOverrideConfigurations(fetchLimit: 1)
            await updateLatestOverrideConfigurationOfState(from: id)
            await setCurrentOverride(from: id)
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
        await overrideStorage.copyRunningOverride(overridePresetToDuplicate)

        // Cancel the duplicated Override
        /// As we are on the Main Thread already we don't need to cancel via the objectID in this case
        do {
            try await viewContext.perform {
                overridePresetToDuplicate.enabled = false

                guard self.viewContext.hasChanges else { return }
                try self.viewContext.save()
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

// MARK: - TEMP TARGET

extension OverrideProfilesConfig.StateModel {
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
            lowTarget = Decimal(round(Double(lowTarget.asMgdL)))
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

extension OverrideProfilesConfig.StateModel: SettingsObserver {
    func settingsDidChange(_: FreeAPSSettings) {
        units = settingsManager.settings.units
        defaultSmbMinutes = settingsManager.preferences.maxSMBBasalMinutes
        defaultUamMinutes = settingsManager.preferences.maxUAMSMBBasalMinutes
        maxValue = settingsManager.preferences.autosensMax
    }
}
