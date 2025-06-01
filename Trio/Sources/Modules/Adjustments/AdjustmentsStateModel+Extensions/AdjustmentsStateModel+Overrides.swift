import Combine
import CoreData
import Foundation
import SwiftUICore

extension Adjustments.StateModel {
    // MARK: - Enact Overrides

    /// Enacts an Override Preset by enabling it and disabling others.
    @MainActor func enactOverridePreset(withID id: NSManagedObjectID) async {
        do {
            guard let overrideToEnact = try viewContext.existingObject(with: id) as? OverrideStored else { return }
            /// Wait for currently active override to be disabled before storing the new one
            await disableAllActiveOverrides(createOverrideRunEntry: currentActiveOverride != nil)
            await resetStateVariables()

            overrideToEnact.enabled = true
            overrideToEnact.date = Date()
            overrideToEnact.isUploadedToNS = false
            isOverrideEnabled = true

            guard viewContext.hasChanges else { return }
            try viewContext.save()

            updateLatestOverrideConfiguration()
        } catch {
            debugPrint("\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to enact Override Preset")
        }
    }

    // MARK: - Disable Overrides

    /// Disables all active Overrides, optionally creating a run entry.
    @MainActor func disableAllActiveOverrides(
        except overrideID: NSManagedObjectID? = nil,
        createOverrideRunEntry: Bool
    ) async {
        do {
            // Get ALL NSManagedObject IDs of ALL active Override to cancel every single Override
            let ids = try await overrideStorage.loadLatestOverrideConfigurations(fetchLimit: 0)

            try await viewContext.perform {
                // Fetch the existing OverrideStored objects from the context
                let results = try ids.compactMap { id in
                    try self.viewContext.existingObject(with: id) as? OverrideStored
                }
                guard !results.isEmpty else { return }

                // Check if we also need to create a corresponding OverrideRunStored entry
                if createOverrideRunEntry {
                    // Use the first override to create a new OverrideRunStored entry
                    if let canceledOverride = results.first {
                        let newOverrideRunStored = OverrideRunStored(context: self.viewContext)
                        newOverrideRunStored.id = UUID()
                        newOverrideRunStored.name = canceledOverride.name
                        newOverrideRunStored.startDate = canceledOverride.date ?? .distantPast
                        newOverrideRunStored.endDate = Date()
                        newOverrideRunStored.target = NSDecimalNumber(
                            decimal: self.overrideStorage.calculateTarget(override: canceledOverride)
                        )
                        newOverrideRunStored.override = canceledOverride
                        newOverrideRunStored.isUploadedToNS = false
                    }
                }

                // Disable all overrides except the one with overrideID
                for overrideToCancel in results where overrideToCancel.objectID != overrideID {
                    overrideToCancel.enabled = false
                }

                if self.viewContext.hasChanges {
                    // Save changes and update the View
                    try self.viewContext.save()
                    self.updateLatestOverrideConfiguration()
                }
            }
        } catch {
            debug(
                .default,
                "\(DebuggingIdentifiers.failed) Failed to disable active overrides: \(error)"
            )
        }
    }

    // MARK: - Save Overrides

    /// Saves a custom Override and activates it.
    func saveCustomOverride() async {
        do {
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
            try await overrideStorage.storeOverride(override: override)

            // Reset State variables
            await resetStateVariables()

            // Update View
            updateLatestOverrideConfiguration()
        } catch {
            debug(
                .default,
                "\(DebuggingIdentifiers.failed) Failed to save custom override: \(error)"
            )
        }
    }

    /// Saves an Override Preset without activating it.
    /// `enabled` has to be false
    /// `isPreset` has to be true
    func saveOverridePreset() async {
        do {
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
            _ = try await (storeOverride, resetState)

            setupOverridePresetsArray()
            try await nightscoutManager.uploadProfiles()
        } catch {
            debug(
                .default,
                "\(DebuggingIdentifiers.failed) Failed to save override preset: \(error)"
            )
        }
    }

    // MARK: - Override Preset Management

    /// Sets up the array of Override Presets for UI display.
    func setupOverridePresetsArray() {
        Task {
            do {
                let ids = try await overrideStorage.fetchForOverridePresets()
                await updateOverridePresetsArray(with: ids)
            } catch {
                debug(
                    .default,
                    "\(DebuggingIdentifiers.failed) Failed to setup override presets: \(error)"
                )
            }
        }
    }

    /// Updates the array of Override Presets from Core Data.
    @MainActor private func updateOverridePresetsArray(with IDs: [NSManagedObjectID]) async {
        do {
            let overrideObjects = try IDs.compactMap { id in
                try viewContext.existingObject(with: id) as? OverrideStored
            }
            overridePresets = overrideObjects
        } catch {
            debugPrint(
                "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to extract Overrides: \(error)"
            )
        }
    }

    /// Deletes an Override Preset and updates the view.
    func invokeOverridePresetDeletion(_ objectID: NSManagedObjectID) async {
        do {
            await overrideStorage.deleteOverridePreset(objectID)
            setupOverridePresetsArray()
            try await nightscoutManager.uploadProfiles()
        } catch {
            debug(
                .default,
                "\(DebuggingIdentifiers.failed) Failed to delete override preset: \(error)"
            )
        }
    }

    // MARK: - Update Latest Override Configuration

    /// Updates the latest Override configuration and state.
    /// First get the latest Overrides corresponding NSManagedObjectID with a background fetch
    /// Then unpack it on the view context and update the State variables which can be used on in the View for some Logic
    /// This also needs to be called when we cancel an Override via the Home View to update the State of the Button for this case
    func updateLatestOverrideConfiguration() {
        Task { [weak self] in
            do {
                guard let self = self else { return }

                let id = try await self.overrideStorage.loadLatestOverrideConfigurations(fetchLimit: 1)

                // execute sequentially instead of concurrently
                await self.updateLatestOverrideConfigurationOfState(from: id)
                await self.setCurrentOverride(from: id)

                // perform determine basal sync to immediately apply override changes
                try await apsManager.determineBasalSync()
            } catch {
                debug(
                    .default,
                    "\(DebuggingIdentifiers.failed) Failed to update override configuration: \(error)"
                )
            }
        }
    }

    /// Updates state variables with the latest Override configuration.
    @MainActor func updateLatestOverrideConfigurationOfState(from IDs: [NSManagedObjectID]) async {
        do {
            let result = try IDs.compactMap { id in
                try viewContext.existingObject(with: id) as? OverrideStored
            }
            isOverrideEnabled = result.first?.enabled ?? false
            if !isOverrideEnabled {
                await resetStateVariables()
            }
        } catch {
            debugPrint("\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to update latest Override configuration")
        }
    }

    /// Sets the current active Override for UI purposes.
    @MainActor func setCurrentOverride(from IDs: [NSManagedObjectID]) async {
        do {
            guard let firstID = IDs.first else {
                activeOverrideName = "Custom Override"
                currentActiveOverride = nil
                return
            }

            if let overrideToEdit = try viewContext.existingObject(with: firstID) as? OverrideStored {
                currentActiveOverride = overrideToEdit
                activeOverrideName = overrideToEdit.name ?? String(localized: "Custom Override")
            }
        } catch {
            debugPrint(
                "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to set active Override: \(error)"
            )
        }
    }

    /// Duplicates the active Override Preset and cancels the previous one.
    @MainActor func duplicateOverridePresetAndCancelPreviousOverride() async {
        guard let overridePresetToDuplicate = currentActiveOverride, overridePresetToDuplicate.isPreset else { return }

        let duplicateId = await overrideStorage.copyRunningOverride(overridePresetToDuplicate)

        do {
            try await viewContext.perform {
                overridePresetToDuplicate.enabled = false
                guard self.viewContext.hasChanges else { return }
                try self.viewContext.save()
            }

            if let overrideToEdit = try viewContext.existingObject(with: duplicateId) as? OverrideStored {
                currentActiveOverride = overrideToEdit
                activeOverrideName = overrideToEdit.name ?? String(localized: "Custom Override")
            }
        } catch {
            debugPrint(
                "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to cancel previous Override: \(error)"
            )
        }
    }

    // MARK: - Helper Functions

    /// Resets state variables to default values.
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

    /// Rounds a target value to the nearest step.
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

    /// Rounds an Override percentage to the nearest step.
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
    case isfAndCr
    case isf
    case cr
    case nothing

    var displayName: String {
        switch self {
        case .isfAndCr:
            return String(localized: "ISF/CR", comment: "Option for both ISF and CR")
        case .isf:
            return String(localized: "ISF", comment: "Option for Insulin Sensitivity Factor")
        case .cr:
            return String(localized: "CR", comment: "Option for Carb Ratio")
        case .nothing:
            return String(localized: "None", comment: "Option for no selection")
        }
    }
}

enum DisableSmbOptions: String, CaseIterable {
    case dontDisable
    case disable
    case disableOnSchedule

    var displayName: String {
        switch self {
        case .dontDisable:
            return String(localized: "Don't Disable", comment: "Option to keep SMB enabled")
        case .disable:
            return String(localized: "Disable", comment: "Option to disable SMB")
        case .disableOnSchedule:
            return String(localized: "Disable on Schedule", comment: "Option to disable SMB based on schedule")
        }
    }
}
