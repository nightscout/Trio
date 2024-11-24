import Combine
import CoreData
import Foundation

extension Adjustments.StateModel {
    // MARK: - Enact Overrides

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
    func setupOverridePresetsArray() {
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
