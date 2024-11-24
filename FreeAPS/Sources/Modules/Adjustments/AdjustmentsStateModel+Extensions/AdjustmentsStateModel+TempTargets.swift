import Combine
import CoreData
import Foundation

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

    func setupTempTargets(
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

    func setupTempTargetPresetsArray() {
        setupTempTargets(
            fetchFunction: tempTargetStorage.fetchForTempTargetPresets,
            updateFunction: { tempTargets in
                self.tempTargetPresets = tempTargets
            }
        )
    }

    func setupScheduledTempTargetsArray() {
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

    func enableScheduledTempTarget(for date: Date) async {
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

enum TempTargetSensitivityAdjustmentType: String, CaseIterable {
    case standard = "Standard"
    case slider = "Custom"
}
