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
        @Published var smbIsScheduledOff: Bool = false
        @Published var start: Decimal = 0
        @Published var end: Decimal = 23
        @Published var smbMinutes: Decimal = 0
        @Published var uamMinutes: Decimal = 0
        @Published var defaultSmbMinutes: Decimal = 0
        @Published var defaultUamMinutes: Decimal = 0
<<<<<<< HEAD
        @Published var selectedTab: Tab = .overrides
        @Published var activeOverrideName: String = ""
        @Published var currentActiveOverride: OverrideStored?
        @Published var showOverrideEditSheet = false
        @Published var showInvalidTargetAlert = false
=======
>>>>>>> 9672da256c317a314acc76d6e4f6e82cc174d133

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

        private var formatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 0
            return formatter
        }

        private var glucoseFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 0
            if units == .mmolL {
                formatter.maximumFractionDigits = 1
            }
            formatter.roundingMode = .halfUp
            return formatter
        }

        override func subscribe() {
            setupNotification()
            units = settingsManager.settings.units
            defaultSmbMinutes = settingsManager.preferences.maxSMBBasalMinutes
            defaultUamMinutes = settingsManager.preferences.maxUAMSMBBasalMinutes
<<<<<<< HEAD
            setupOverridePresetsArray()
            updateLatestOverrideConfiguration()
            presetsTT = storage.presets()
            maxValue = settingsManager.preferences.autosensMax
            broadcaster.register(SettingsObserver.self, observer: self)
=======
            presets = [OverridePresets(context: coredataContext)]
>>>>>>> 9672da256c317a314acc76d6e4f6e82cc174d133
        }

        let coredataContext = CoreDataStack.shared.newTaskContext()
        let viewContext = CoreDataStack.shared.persistentContainer.viewContext

<<<<<<< HEAD
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
=======
        struct ProfileViewData {
            let target: Decimal
            let duration: Decimal
            let name: String
            let percent: Double
            let perpetual: Bool
            let durationString: String
            let scheduledSMBString: String
            let smbString: String
            let targetString: String
            let maxMinutesSMB: Decimal
            let maxMinutesUAM: Decimal
            let isfString: String
            let crString: String
            let isfAndCRString: String
        }

        func profileViewData(for preset: OverridePresets) -> ProfileViewData {
            let target = units == .mmolL ? (((preset.target ?? 0) as NSDecimalNumber) as Decimal)
                .asMmolL : (preset.target ?? 0) as Decimal
            let duration = (preset.duration ?? 0) as Decimal
            let name = ((preset.name ?? "") == "") || (preset.name?.isEmpty ?? true) ? "" : preset.name!
            let percent = preset.percentage / 100
            let perpetual = preset.indefinite
            let durationString = perpetual ? "" : "\(formatter.string(from: duration as NSNumber)!)"
            let scheduledSMBString = (preset.smbIsOff && preset.smbIsScheduledOff) ? "Scheduled SMBs" : ""
            let smbString = (preset.smbIsOff && scheduledSMBString == "") ? "SMBs are off" : ""
            let targetString = target != 0 ? "\(glucoseFormatter.string(from: target as NSNumber)!)" : ""
            let maxMinutesSMB = (preset.smbMinutes as Decimal?) != nil ? (preset.smbMinutes ?? 0) as Decimal : 0
            let maxMinutesUAM = (preset.uamMinutes as Decimal?) != nil ? (preset.uamMinutes ?? 0) as Decimal : 0
            let isfString = preset.isf ? "ISF" : ""
            let crString = preset.cr ? "CR" : ""
            let dash = crString != "" ? "/" : ""
            let isfAndCRString = isfString + dash + crString

            return ProfileViewData(
                target: target,
                duration: duration,
                name: name,
                percent: percent,
                perpetual: perpetual,
                durationString: durationString,
                scheduledSMBString: scheduledSMBString,
                smbString: smbString,
                targetString: targetString,
                maxMinutesSMB: maxMinutesSMB,
                maxMinutesUAM: maxMinutesUAM,
                isfString: isfString,
                crString: crString,
                isfAndCRString: isfAndCRString
            )
        }

        func saveSettings() {
            coredataContext.perform { [self] in
                let saveOverride = Override(context: self.coredataContext)
                saveOverride.duration = self.duration as NSDecimalNumber
                saveOverride.indefinite = self._indefinite
                saveOverride.percentage = self.percentage
                saveOverride.enabled = true
                saveOverride.smbIsOff = self.smbIsOff
                if self.isPreset {
                    saveOverride.isPreset = true
                    saveOverride.id = id
                } else { saveOverride.isPreset = false }
                saveOverride.date = Date()
                if override_target {
                    if units == .mmolL {
                        target = target.asMgdL
                    }
                    saveOverride.target = target as NSDecimalNumber
                } else { saveOverride.target = 0 }

                if advancedSettings {
                    saveOverride.advancedSettings = true

                    if !isfAndCr {
                        saveOverride.isfAndCr = false
                        saveOverride.isf = isf
                        saveOverride.cr = cr
                    } else { saveOverride.isfAndCr = true }
                    if smbIsScheduledOff {
                        saveOverride.smbIsScheduledOff = true
                        saveOverride.start = start as NSDecimalNumber
                        saveOverride.end = end as NSDecimalNumber
                    } else { saveOverride.smbIsScheduledOff = false }

                    saveOverride.smbMinutes = smbMinutes as NSDecimalNumber
                    saveOverride.uamMinutes = uamMinutes as NSDecimalNumber
                }
                try? self.coredataContext.save()
            }
        }

        func savePreset() {
            coredataContext.perform { [self] in
                let saveOverride = OverridePresets(context: self.coredataContext)
                saveOverride.duration = self.duration as NSDecimalNumber
                saveOverride.indefinite = self._indefinite
                saveOverride.percentage = self.percentage
                saveOverride.smbIsOff = self.smbIsOff
                saveOverride.name = self.profileName
                self.profileName = ""
                id = UUID().uuidString
                self.isPreset.toggle()
                saveOverride.id = id
                saveOverride.date = Date()
                if override_target {
                    saveOverride.target = (
                        units == .mmolL
                            ? target.asMgdL
                            : target
                    ) as NSDecimalNumber
                } else { saveOverride.target = 0 }

                if advancedSettings {
                    saveOverride.advancedSettings = true

                    if !isfAndCr {
                        saveOverride.isfAndCr = false
                        saveOverride.isf = isf
                        saveOverride.cr = cr
                    } else { saveOverride.isfAndCr = true }
                    if smbIsScheduledOff {
                        saveOverride.smbIsScheduledOff = true
                        saveOverride.start = start as NSDecimalNumber
                        saveOverride.end = end as NSDecimalNumber
                    } else { smbIsScheduledOff = false }

                    saveOverride.smbMinutes = smbMinutes as NSDecimalNumber
                    saveOverride.uamMinutes = uamMinutes as NSDecimalNumber
                }
                try? self.coredataContext.save()
            }
        }

        func selectProfile(id_: String) {
            guard id_ != "" else { return }
            coredataContext.performAndWait {
                var profileArray = [OverridePresets]()
                let requestProfiles = OverridePresets.fetchRequest() as NSFetchRequest<OverridePresets>
                try? profileArray = coredataContext.fetch(requestProfiles)

                guard let profile = profileArray.filter({ $0.id == id_ }).first else { return }

                let saveOverride = Override(context: self.coredataContext)
                saveOverride.duration = (profile.duration ?? 0) as NSDecimalNumber
                saveOverride.indefinite = profile.indefinite
                saveOverride.percentage = profile.percentage
                saveOverride.enabled = true
                saveOverride.smbIsOff = profile.smbIsOff
                saveOverride.isPreset = true
                saveOverride.date = Date()
                saveOverride.target = profile.target
                saveOverride.id = id_

                if profile.advancedSettings {
                    saveOverride.advancedSettings = true
                    if !isfAndCr {
                        saveOverride.isfAndCr = false
                        saveOverride.isf = profile.isf
                        saveOverride.cr = profile.cr
                    } else { saveOverride.isfAndCr = true }
                    if profile.smbIsScheduledOff {
                        saveOverride.smbIsScheduledOff = true
                        saveOverride.start = profile.start
                        saveOverride.end = profile.end
                    } else { saveOverride.smbIsScheduledOff = false }

                    saveOverride.smbMinutes = (profile.smbMinutes ?? 0) as NSDecimalNumber
                    saveOverride.uamMinutes = (profile.uamMinutes ?? 0) as NSDecimalNumber
                }
                try? self.coredataContext.save()
            }
        }

        func savedSettings() {
            coredataContext.performAndWait {
                var overrideArray = [Override]()
                let requestEnabled = Override.fetchRequest() as NSFetchRequest<Override>
                let sortIsEnabled = NSSortDescriptor(key: "date", ascending: false)
                requestEnabled.sortDescriptors = [sortIsEnabled]
                try? overrideArray = coredataContext.fetch(requestEnabled)
                isEnabled = overrideArray.first?.enabled ?? false
                percentage = overrideArray.first?.percentage ?? 100
                _indefinite = overrideArray.first?.indefinite ?? true
                duration = (overrideArray.first?.duration ?? 0) as Decimal
                smbIsOff = overrideArray.first?.smbIsOff ?? false
                advancedSettings = overrideArray.first?.advancedSettings ?? false
                isfAndCr = overrideArray.first?.isfAndCr ?? true
                smbIsScheduledOff = overrideArray.first?.smbIsScheduledOff ?? false

                if advancedSettings {
                    if !isfAndCr {
                        isf = overrideArray.first?.isf ?? false
                        cr = overrideArray.first?.cr ?? false
                    }
                    if smbIsScheduledOff {
                        start = (overrideArray.first?.start ?? 0) as Decimal
                        end = (overrideArray.first?.end ?? 0) as Decimal
                    }

                    if (overrideArray[0].smbMinutes as Decimal?) != nil {
                        smbMinutes = (overrideArray.first?.smbMinutes ?? 30) as Decimal
                    }

                    if (overrideArray[0].uamMinutes as Decimal?) != nil {
                        uamMinutes = (overrideArray.first?.uamMinutes ?? 30) as Decimal
                    }
                }

                let overrideTarget = (overrideArray.first?.target ?? 0) as Decimal

                var newDuration = Double(duration)
                if isEnabled {
                    let duration = overrideArray.first?.duration ?? 0
                    let addedMinutes = Int(duration as Decimal)
                    let date = overrideArray.first?.date ?? Date()
                    if date.addingTimeInterval(addedMinutes.minutes.timeInterval) < Date(), !_indefinite {
                        isEnabled = false
                    }
                    newDuration = Date().distance(to: date.addingTimeInterval(addedMinutes.minutes.timeInterval)).minutes
                    if overrideTarget != 0 {
                        override_target = true
                        target = units == .mmolL ? overrideTarget.asMmolL : overrideTarget
                    }
                }

                if newDuration < 0 { newDuration = 0 } else { duration = Decimal(newDuration) }

                if !isEnabled {
                    _indefinite = true
                    percentage = 100
                    duration = 0
                    target = 0
                    override_target = false
                    smbIsOff = false
                    advancedSettings = false
                    smbMinutes = defaultSmbMinutes
                    uamMinutes = defaultUamMinutes
                }
            }
        }

        func populateSettings(from preset: OverridePresets) {
            profileName = preset.name ?? ""
            percentage = preset.percentage
            duration = (preset.duration ?? 0) as Decimal
            _indefinite = preset.indefinite
            override_target = preset.target != nil
            if let targetValue = preset.target as NSDecimalNumber? {
                target = units == .mmolL ? (targetValue as Decimal).asMmolL : targetValue as Decimal
            } else {
                target = 0
            }
            advancedSettings = preset.advancedSettings
            smbIsOff = preset.smbIsOff
            smbIsScheduledOff = preset.smbIsScheduledOff
            isf = preset.isf
            cr = preset.cr
            smbMinutes = (preset.smbMinutes ?? 0) as Decimal
            uamMinutes = (preset.uamMinutes ?? 0) as Decimal
            isfAndCr = preset.isfAndCr
            start = (preset.start ?? 0) as Decimal
            end = (preset.end ?? 0) as Decimal
        }

        func cancelProfile() {
            _indefinite = true
            isEnabled = false
            percentage = 100
            duration = 0
            target = 0
            override_target = false
            smbIsOff = false
            advancedSettings = false
            coredataContext.perform { [self] in
                let profiles = Override(context: self.coredataContext)
                profiles.enabled = false
                profiles.date = Date()
                try? self.coredataContext.save()
>>>>>>> 9672da256c317a314acc76d6e4f6e82cc174d133
            }
            smbMinutes = defaultSmbMinutes
            uamMinutes = defaultUamMinutes
        }

        func updatePreset(_ preset: OverridePresets) {
            let context = CoreDataStack.shared.persistentContainer.viewContext
            context.performAndWait {
                preset.name = profileName
                preset.percentage = percentage
                preset.duration = NSDecimalNumber(decimal: duration)
                let targetValue = override_target ? (units == .mmolL ? target.asMgdL : target) : nil
                preset.target = targetValue != nil ? NSDecimalNumber(decimal: targetValue!) : nil
                preset.indefinite = _indefinite
                preset.advancedSettings = advancedSettings
                preset.smbIsOff = smbIsOff
                preset.smbIsScheduledOff = smbIsScheduledOff
                preset.isf = isf
                preset.cr = cr
                preset.smbMinutes = NSDecimalNumber(decimal: smbMinutes)
                preset.uamMinutes = NSDecimalNumber(decimal: uamMinutes)
                preset.isfAndCr = isfAndCr
                try? context.save()
            }
        }
    }
}

// MARK: - Setup Notifications

extension OverrideProfilesConfig.StateModel {
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
