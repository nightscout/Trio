import CoreData
import SwiftUI

extension OverrideProfilesConfig {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() var storage: TempTargetsStorage!
        @Injected() var apsManager: APSManager!

        @Published var percentageProfiles: Double = 100
        @Published var isEnabled = false
        @Published var _indefinite = true
        @Published var durationProfile: Decimal = 0
        @Published var target: Decimal = 0
        @Published var override_target: Bool = false
        @Published var smbIsOff: Bool = false
        @Published var id: String = ""
        @Published var profileName: String = ""
        @Published var isPreset: Bool = false
        @Published var profilePresets: [OverrideStored] = []
        @Published var selection: OverrideStored?
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
        @Published var selectedTab: Tab = .profiles
        @Published var activeOverrideName: String = ""
        @Published var currentActiveOverride: OverrideStored?

        var units: GlucoseUnits = .mmolL

        // temp target stuff
        @Published var low: Decimal = 0
        // @Published var target: Decimal = 0
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

        private var dateFormatter: DateFormatter {
            let df = DateFormatter()
            df.dateFormat = "dd.MM.yy HH:mm"
            return df
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
        }

        let coredataContext = CoreDataStack.shared.newTaskContext()
        let viewContext = CoreDataStack.shared.persistentContainer.viewContext
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
    ///
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
}

// MARK: - Enact Overrides

extension OverrideProfilesConfig.StateModel {
    func scheduleOverrideDisabling(for override: OverrideStored) {
        let now = Date()
        guard let toCancelDuration = override.duration,
              let endTime = override.date?
              .addingTimeInterval(
                  TimeInterval(truncating: toCancelDuration) *
                      60
              ) // ensuring duration is minutes, not seconds!
        else {
            debugPrint("\(DebuggingIdentifiers.failed) \(#file) \(#function) End time calculation failed")
            return
        }

        debugPrint(
            "\(DebuggingIdentifiers.inProgress) \(#file) \(#function) Scheduling cancellation at \(endTime) (in \(endTime.timeIntervalSince(now)) seconds)"
        )

        guard endTime > now else {
            debugPrint("\(DebuggingIdentifiers.failed) \(#file) \(#function) End time is in the past or now")
            return
        }

        let timeInterval = endTime.timeIntervalSince(now)

        DispatchQueue.main.asyncAfter(deadline: .now() + timeInterval) { [weak self] in
            debugPrint("\(DebuggingIdentifiers.inProgress) \(#file) \(#function) Executing scheduled cancelActiveProfile")
            self?.cancelActiveProfile()
        }
    }

    // Enact Preset
    /// here we only have to update the Boolean Flag 'enabled'
    @MainActor func enactProfilePreset(withID id: NSManagedObjectID) async {
        do {
            /// get the underlying NSManagedObject of the Profile that should be enabled
            let profileToEnact = try viewContext.existingObject(with: id) as? OverrideStored
            profileToEnact?.enabled = true
            profileToEnact?.date = Date()

            /// Update the 'Cancel Profile' button state
            isEnabled = true

            /// disable all active Profiles and reset state variables
            await disableAllActiveProfiles(except: id)
            await resetStateVariables()

            if let toSchedule = profileToEnact {
                scheduleOverrideDisabling(for: toSchedule)
            }

            guard viewContext.hasChanges else { return }
            try viewContext.save()
        } catch {
            debugPrint("\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to enact Profile Preset")
        }
    }
}

// MARK: - Profile (presets) save operations

extension OverrideProfilesConfig.StateModel {
    // Saves Profile in a background context
    /// not a Preset
    func saveAsProfile() async {
        await coredataContext.perform { [self] in
            let newProfile = OverrideStored(context: self.coredataContext)
            if self.profileName.isNotEmpty {
                newProfile.name = self.profileName
            } else {
                let formattedDate = dateFormatter.string(from: Date())
                newProfile.name = "Preset <\(formattedDate)>"
            }
            newProfile.duration = self.durationProfile as NSDecimalNumber
            newProfile.indefinite = self._indefinite
            newProfile.percentage = self.percentageProfiles
            newProfile.enabled = true
            newProfile.smbIsOff = self.smbIsOff
            if self.isPreset {
                newProfile.isPreset = true
                newProfile.id = id
            } else { newProfile.isPreset = false }
            newProfile.date = Date()
            if override_target {
                if units == .mmolL {
                    target = target.asMgdL
                }
                newProfile.target = target as NSDecimalNumber
            } else { newProfile.target = 0 }

            if advancedSettings {
                newProfile.advancedSettings = true

                if !isfAndCr {
                    newProfile.isfAndCr = false
                    newProfile.isf = isf
                    newProfile.cr = cr
                } else { newProfile.isfAndCr = true }
                if smbIsAlwaysOff {
                    newProfile.smbIsAlwaysOff = true
                    newProfile.start = start as NSDecimalNumber
                    newProfile.end = end as NSDecimalNumber
                } else { newProfile.smbIsAlwaysOff = false }

                newProfile.smbMinutes = smbMinutes as NSDecimalNumber
                newProfile.uamMinutes = uamMinutes as NSDecimalNumber
            }
            do {
                guard coredataContext.hasChanges else { return }
                try coredataContext.save()
                self.scheduleOverrideDisabling(for: newProfile)
            } catch {
                print(error.localizedDescription)
            }
        }
    }

    // Save Presets
    /// enabled has to be false, isPreset has to be true
    func savePreset() async {
        await coredataContext.perform { [self] in
            let newOverride = OverrideStored(context: self.coredataContext)
            newOverride.duration = self.durationProfile as NSDecimalNumber
            newOverride.indefinite = self._indefinite
            newOverride.percentage = self.percentageProfiles
            newOverride.smbIsOff = self.smbIsOff
            if self.profileName.isNotEmpty {
                newOverride.name = self.profileName
            } else {
                let formattedDate = dateFormatter.string(from: Date())
                newOverride.name = "Profile \(formattedDate)"
            }
            newOverride.isPreset = true
            newOverride.date = Date()
            newOverride.enabled = false

            if override_target {
                newOverride.target = (
                    units == .mmolL
                        ? target.asMgdL
                        : target
                ) as NSDecimalNumber
            }

            if advancedSettings {
                newOverride.advancedSettings = true

                if !isfAndCr {
                    newOverride.isfAndCr = false
                    newOverride.isf = isf
                    newOverride.cr = cr
                } else { newOverride.isfAndCr = true }
                if smbIsAlwaysOff {
                    newOverride.smbIsAlwaysOff = true
                    newOverride.start = start as NSDecimalNumber
                    newOverride.end = end as NSDecimalNumber
                } else { newOverride.smbIsAlwaysOff = false }

                newOverride.smbMinutes = smbMinutes as NSDecimalNumber
                newOverride.uamMinutes = uamMinutes as NSDecimalNumber
            }
            do {
                guard coredataContext.hasChanges else { return }
                try coredataContext.save()

                /// Custom Notification to update Presets View
                Foundation.NotificationCenter.default.post(name: .didUpdateOverridePresets, object: nil)

                /// prevent showing the current config of the recently added Preset
                Task {
                    await resetStateVariables()
                }
            } catch let error as NSError {
                debugPrint(
                    "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to save Override Preset to Core Data with error: \(error.userInfo)"
                )
            }
        }
    }
}

// MARK: - Setup Override Presets Array

extension OverrideProfilesConfig.StateModel {
    // Fill the array of the Profile Presets to display them in the UI
    private func setupOverridePresetsArray() {
        Task {
            let ids = await self.fetchForProfilePresets()
            await updateOverridePresetsArray(with: ids)
        }
    }

    /// Returns the NSManagedObjectID of the Override Presets
    private func fetchForProfilePresets() async -> [NSManagedObjectID] {
        let result = await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: OverrideStored.self,
            onContext: coredataContext,
            predicate: NSPredicate.allOverridePresets,
            key: "name",
            ascending: true
        )

        return await coredataContext.perform {
            return result.map(\.objectID)
        }
    }

    @MainActor private func updateOverridePresetsArray(with IDs: [NSManagedObjectID]) async {
        do {
            let overrideObjects = try IDs.compactMap { id in
                try viewContext.existingObject(with: id) as? OverrideStored
            }
            profilePresets = overrideObjects
        } catch {
            debugPrint(
                "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to extract Overrides as NSManagedObjects from the NSManagedObjectIDs with error: \(error.localizedDescription)"
            )
        }
    }
}

// MARK: - Profile Cancelling

extension OverrideProfilesConfig.StateModel {
    /// Gets the corresponding NSManagedObjectID of the current active Profile and cancels it
    func cancelActiveProfile() {
        Task {
            let id = await getActiveProfile()
            await cancelActiveProfile(withID: id)
        }
    }

    func getActiveProfile() async -> NSManagedObjectID? {
        let results = await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: OverrideStored.self,
            onContext: coredataContext,
            predicate: NSPredicate.lastActiveOverride,
            key: "date",
            ascending: false,
            fetchLimit: 1
        )

        return await coredataContext.perform {
            return results.first.map(\.objectID)
        }
    }

    @MainActor func cancelActiveProfile(withID id: NSManagedObjectID?) async {
        guard let id = id else { return }

        return await viewContext.perform {
            do {
                let profileToCancel = try self.viewContext.existingObject(with: id) as? OverrideStored
                profileToCancel?.enabled = false

                /// Update the 'Cancel Profile' button state
                self.isEnabled = false

                guard self.viewContext.hasChanges else { return }
                try self.viewContext.save()
            } catch {
                debugPrint(
                    "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to cancel Profile with error: \(error.localizedDescription)"
                )
            }
        }
    }

    /// Gets the corresponding NSManagedObjectIDs of all active Profiles and cancels them
    @MainActor func disableAllActiveProfiles(except profileID: NSManagedObjectID? = nil) async {
        /// get all NSManagedObject IDs of all active Profiles
        let ids = await loadLatestOverrideConfigurations(fetchLimit: 0) /// 0 = no fetch limit

        /// end all active profiles
        do {
            let results = try ids.compactMap { id in
                try viewContext.existingObject(with: id) as? OverrideStored
            }

            for profile in results {
                if profile.objectID != profileID {
                    profile.enabled = false
                }
            }

            try await viewContext.perform {
                guard self.viewContext.hasChanges else { return }
                try self.viewContext.save()
            }
        } catch {
            debugPrint(
                "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to disable active Profiles with error: \(error.localizedDescription)"
            )
        }
    }
}

// MARK: - Setup the State variables with the last Override configuration

extension OverrideProfilesConfig.StateModel {
    /// First get the latest Overrides corresponding NSManagedObjectID with a background fetch
    /// Then unpack it on the view context and update the State variables which can be used on in the View for some Logic
    /// This also needs to be called when we cancel a Profile via the Home View to update the State of the Button for this case
    func updateLatestOverrideConfiguration() {
        Task {
            let id = await loadLatestOverrideConfigurations(fetchLimit: 1)

            await updateLatestOverrideConfigurationOfState(from: id)
            await setCurrentOverrideName(from: id)
        }
    }

    func loadLatestOverrideConfigurations(fetchLimit: Int) async -> [NSManagedObjectID] {
        let results = await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: OverrideStored.self,
            onContext: coredataContext,
            predicate: NSPredicate.lastActiveOverride,
            key: "date",
            ascending: false,
            fetchLimit: fetchLimit
        )

        return await coredataContext.perform {
            return results.map(\.objectID)
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

    /// Sets the current active Preset name to show in the UI
    @MainActor func setCurrentOverrideName(from IDs: [NSManagedObjectID]) async {
        do {
            guard let firstID = IDs.first else {
                activeOverrideName = "Custom Override"
                currentActiveOverride = nil
                return
            }

            if let overrideToEdit = try viewContext.existingObject(with: firstID) as? OverrideStored {
                if overrideToEdit.isPreset {
                    await handlePresetOverride(overrideToEdit)
                } else {
                    currentActiveOverride = overrideToEdit
                    activeOverrideName = overrideToEdit.name ?? "Custom Override"
                }
            }
        } catch {
            debugPrint(
                "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to set active preset name with error: \(error.localizedDescription)"
            )
        }
    }

    @MainActor private func handlePresetOverride(_ overrideToEdit: OverrideStored) async {
        do {
            await copyOverride(overrideToEdit)
            await cancelActiveProfile(withID: overrideToEdit.objectID)

            let ids = await loadLatestOverrideConfigurations(fetchLimit: 1)
            if let copiedID = ids.first,
               let copiedOverride = try viewContext.existingObject(with: copiedID) as? OverrideStored
            {
                currentActiveOverride = copiedOverride
                activeOverrideName = copiedOverride.name ?? "Custom Override"
            }
        } catch {
            debugPrint(
                "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to handle preset override with error: \(error.localizedDescription)"
            )
        }
    }
}

// MARK: - Profile Preset Deletion

extension OverrideProfilesConfig.StateModel {
    /// marked as MainActor to be able to publish changes from the background
    /// - Parameter: NSManagedObjectID to be able to transfer the object safely from one thread to another thread
    @MainActor func invokeProfilePresetDeletion(_ objectID: NSManagedObjectID) {
        Task {
            await deleteProfile(objectID)
        }
    }

    private func deleteProfile(_ objectID: NSManagedObjectID) async {
        CoreDataStack.shared.deleteObject(identifiedBy: objectID)
    }
}

// MARK: - Helper functions for Overrides

extension OverrideProfilesConfig.StateModel {
    @MainActor func resetStateVariables() async {
        durationProfile = 0
        _indefinite = true
        percentageProfiles = 100

        advancedSettings = false
        smbIsOff = false
        profileName = ""
        override_target = false
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

    // Copy the current Override if it is a running Preset
    /// otherwise we would edit the current running Preset
    @MainActor private func copyOverride(_ override: OverrideStored) async {
        let newOverride = OverrideStored(context: viewContext)
        newOverride.duration = override.duration
        newOverride.indefinite = override.indefinite
        newOverride.percentage = override.percentage
        newOverride.smbIsOff = override.smbIsOff
        newOverride.name = override.name
        newOverride.isPreset = false // no Preset
        newOverride.date = Date()
        newOverride.enabled = override.enabled
        newOverride.target = override.target
        newOverride.advancedSettings = override.advancedSettings
        newOverride.isfAndCr = override.isfAndCr
        newOverride.isf = override.isf
        newOverride.cr = override.cr
        newOverride.smbIsAlwaysOff = override.smbIsAlwaysOff
        newOverride.start = override.start
        newOverride.end = override.end
        newOverride.smbMinutes = override.smbMinutes
        newOverride.uamMinutes = override.uamMinutes

        await viewContext.perform {
            do {
                guard self.viewContext.hasChanges else { return }
                try self.viewContext.save()
            } catch let error as NSError {
                debugPrint(
                    "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to copy Override with error: \(error.userInfo)"
                )
            }
        }
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
