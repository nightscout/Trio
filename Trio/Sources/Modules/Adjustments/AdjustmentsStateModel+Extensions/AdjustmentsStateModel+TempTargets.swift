import Combine
import CoreData
import Foundation

extension Adjustments.StateModel {
    // MARK: - State Initialization and Updates

    /// Updates the latest Temp Target configuration for UI state and logic.
    /// First get the latest Temp Target corresponding NSManagedObjectID with a background fetch
    /// Then unpack it on the view context and update the State variables which can be used on in the View for some Logic
    /// This also needs to be called when we cancel an Temp Target via the Home View to update the State of the Button for this case
    func updateLatestTempTargetConfiguration() {
        Task {
            do {
                let id = try await tempTargetStorage.loadLatestTempTargetConfigurations(fetchLimit: 1)
                async let updateState: () = updateLatestTempTargetConfigurationOfState(from: id)
                async let setTempTarget: () = setCurrentTempTarget(from: id)
                _ = await (updateState, setTempTarget)

                // perform determine basal sync to immediately apply temp target changes
                try await apsManager.determineBasalSync()
            } catch {
                debug(
                    .default,
                    "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to load latest temp target configuration with error: \(error)"
                )
            }
        }
    }

    /// Updates state variables with the latest Temp Target configuration.
    @MainActor func updateLatestTempTargetConfigurationOfState(from IDs: [NSManagedObjectID]) async {
        do {
            let result = try IDs.compactMap { id in
                try viewContext.existingObject(with: id) as? TempTargetStored
            }
            isTempTargetEnabled = result.first?.enabled ?? false
            if !isOverrideEnabled {
                await resetTempTargetState()
            }
        } catch {
            debugPrint("\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to update latest temp target configuration")
        }
    }

    /// Sets the current Temp Target for UI and logic purposes.
    @MainActor func setCurrentTempTarget(from IDs: [NSManagedObjectID]) async {
        do {
            guard let firstID = IDs.first else {
                activeTempTargetName = "Custom Temp Target"
                currentActiveTempTarget = nil
                return
            }

            if let tempTargetToEdit = try viewContext.existingObject(with: firstID) as? TempTargetStored {
                currentActiveTempTarget = tempTargetToEdit
                activeTempTargetName = tempTargetToEdit.name ?? String(localized: "Custom Temp Target")
                tempTargetTarget = tempTargetToEdit.target?.decimalValue ?? 0
            }
        } catch {
            debugPrint(
                "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to set active preset name with error: \(error)"
            )
        }
    }

    // MARK: - Temp Target Fetching and Setup

    /// Sets up Temp Targets using fetch and update functions.
    func setupTempTargets(
        fetchFunction: @escaping () async throws -> [NSManagedObjectID],
        updateFunction: @escaping @MainActor([TempTargetStored]) -> Void
    ) {
        Task {
            do {
                let ids = try await fetchFunction()
                let tempTargetObjects = await fetchTempTargetObjects(for: ids)
                await updateFunction(tempTargetObjects)
            } catch {
                debug(
                    .default,
                    "\(DebuggingIdentifiers.failed) Failed to setup temp targets: \(error)"
                )
            }
        }
    }

    /// Fetches Temp Target objects from Core Data.
    @MainActor private func fetchTempTargetObjects(for IDs: [NSManagedObjectID]) async -> [TempTargetStored] {
        do {
            return try IDs.compactMap { id in
                try viewContext.existingObject(with: id) as? TempTargetStored
            }
        } catch {
            debugPrint("\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to fetch Temp Targets")
            return []
        }
    }

    /// Sets up the Temp Target presets array for the view.
    func setupTempTargetPresetsArray() {
        setupTempTargets(
            fetchFunction: { try await self.tempTargetStorage.fetchForTempTargetPresets() },
            updateFunction: { tempTargets in
                self.tempTargetPresets = tempTargets
            }
        )
    }

    /// Sets up the scheduled Temp Targets array for the view.
    func setupScheduledTempTargetsArray() {
        setupTempTargets(
            fetchFunction: { try await self.tempTargetStorage.fetchScheduledTempTargets() },
            updateFunction: { tempTargets in
                self.scheduledTempTargets = tempTargets
            }
        )
    }

    // MARK: - Temp Target Creation and Management

    /// Saves a Temp Target to storage.
    func saveTempTargetToStorage(tempTargets: [TempTarget]) {
        tempTargetStorage.saveTempTargetsToStorage(tempTargets)
    }

    /// Saves a Temp Target based on whether it is scheduled or custom.
    func invokeSaveOfCustomTempTargets() async throws {
        if date > Date() {
            try await saveScheduledTempTarget()
        } else {
            try await saveCustomTempTarget()
        }
    }

    /// Saves a scheduled Temp Target and activates it at the specified date.
    func saveScheduledTempTarget() async throws {
        let date = self.date
        guard date > Date() else { return }

        let tempTarget = TempTarget(
            name: tempTargetName,
            createdAt: date,
            targetTop: tempTargetTarget,
            targetBottom: tempTargetTarget,
            duration: tempTargetDuration,
            enteredBy: TempTarget.local,
            reason: TempTarget.custom,
            isPreset: false,
            enabled: false,
            halfBasalTarget: halfBasalTarget
        )
        try await tempTargetStorage.storeTempTarget(tempTarget: tempTarget)
        setupScheduledTempTargetsArray()
        await waitUntilDate(date)
        await disableAllActiveTempTargets(createTempTargetRunEntry: true)
        await enableScheduledTempTarget(for: date)
        tempTargetStorage.saveTempTargetsToStorage([tempTarget])
    }

    /// Enables a scheduled Temp Target for a specific date.
    func enableScheduledTempTarget(for date: Date) async {
        do {
            let ids = try await tempTargetStorage.fetchScheduledTempTarget(for: date)
            guard let firstID = ids.first else {
                debug(.default, "No Temp Target found for the specified date.")
                return
            }
            await setCurrentTempTarget(from: ids)

            try await MainActor.run {
                guard let tempTarget = try viewContext.existingObject(with: firstID) as? TempTargetStored else {
                    throw NSError(
                        domain: "TempTarget",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Failed to find temp target"]
                    )
                }

                tempTarget.enabled = true
                try viewContext.save()
                isTempTargetEnabled = true
            }

            setupScheduledTempTargetsArray()
        } catch {
            debug(
                .default,
                "\(DebuggingIdentifiers.failed) Failed to enable scheduled temp target: \(error)"
            )
        }
    }

    /// Waits until a target date before proceeding.
    private func waitUntilDate(_ targetDate: Date) async {
        while Date() < targetDate {
            let timeInterval = targetDate.timeIntervalSince(Date())
            let sleepDuration = min(timeInterval, 60.0)
            try? await Task.sleep(nanoseconds: UInt64(sleepDuration * 1_000_000_000))
        }
    }

    /// Saves a custom Temp Target and disables existing ones.
    func saveCustomTempTarget() async throws {
        await disableAllActiveTempTargets(createTempTargetRunEntry: true)
        let tempTarget = TempTarget(
            name: tempTargetName,
            /// We don't need to use the state var date here as we are using a different function for scheduled Temp Targets 'saveScheduledTempTarget()'
            createdAt: Date(),
            targetTop: tempTargetTarget,
            targetBottom: tempTargetTarget,
            duration: tempTargetDuration,
            enteredBy: TempTarget.local,
            reason: TempTarget.custom,
            isPreset: false,
            enabled: true,
            halfBasalTarget: halfBasalTarget
        )
        try await tempTargetStorage.storeTempTarget(tempTarget: tempTarget)
        tempTargetStorage.saveTempTargetsToStorage([tempTarget])
        await resetTempTargetState()
        isTempTargetEnabled = true
        updateLatestTempTargetConfiguration()
    }

    /// Creates a new Temp Target preset.
    func saveTempTargetPreset() async throws {
        let tempTarget = TempTarget(
            name: tempTargetName,
            createdAt: Date(),
            targetTop: tempTargetTarget,
            targetBottom: tempTargetTarget,
            duration: tempTargetDuration,
            enteredBy: TempTarget.local,
            reason: TempTarget.custom,
            isPreset: true,
            enabled: false,
            halfBasalTarget: halfBasalTarget
        )
        try await tempTargetStorage.storeTempTarget(tempTarget: tempTarget)
        await resetTempTargetState()
        setupTempTargetPresetsArray()
    }

    /// Enacts a Temp Target preset by enabling it.
    @MainActor func enactTempTargetPreset(withID id: NSManagedObjectID) async {
        do {
            guard let tempTargetToEnact = try viewContext.existingObject(with: id) as? TempTargetStored else { return }
            /// Wait for currently active temp target to be disabled before storing the new temp target
            await disableAllActiveTempTargets(createTempTargetRunEntry: true)
            await resetTempTargetState()

            tempTargetToEnact.enabled = true
            tempTargetToEnact.date = Date()
            tempTargetToEnact.isUploadedToNS = false
            isTempTargetEnabled = true
            if viewContext.hasChanges {
                try viewContext.save()
            }

            updateLatestTempTargetConfiguration()

            let tempTarget = TempTarget(
                name: tempTargetToEnact.name,
                createdAt: Date(),
                targetTop: tempTargetToEnact.target?.decimalValue,
                targetBottom: tempTargetToEnact.target?.decimalValue,
                duration: tempTargetToEnact.duration?.decimalValue ?? 0,
                enteredBy: TempTarget.local,
                reason: TempTarget.custom,
                isPreset: true,
                enabled: true,
                halfBasalTarget: halfBasalTarget
            )
            tempTargetStorage.saveTempTargetsToStorage([tempTarget])
        } catch {
            debugPrint("\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to enact TempTarget Preset")
        }
    }

    /// Disables all active Temp Targets.
    @MainActor func disableAllActiveTempTargets(
        except id: NSManagedObjectID? = nil,
        createTempTargetRunEntry: Bool
    ) async {
        do {
            // Get ALL NSManagedObject IDs of ALL active Temp Targets to cancel every single Temp Target
            let ids = try await tempTargetStorage.loadLatestTempTargetConfigurations(fetchLimit: 0) // 0 = no fetch limit

            try await viewContext.perform {
                // Fetch the existing TempTargetStored objects from the context
                let results = try ids.compactMap { id in
                    try self.viewContext.existingObject(with: id) as? TempTargetStored
                }

                // If there are no results, return early
                guard !results.isEmpty else { return }

                // Check if we also need to create a corresponding TempTargetRunStored entry
                if createTempTargetRunEntry {
                    // Use the first temp target to create a new TempTargetRunStored entry
                    if let canceledTempTarget = results.first {
                        let newTempTargetRunStored = TempTargetRunStored(context: self.viewContext)
                        newTempTargetRunStored.id = UUID()
                        newTempTargetRunStored.name = canceledTempTarget.name
                        newTempTargetRunStored.startDate = canceledTempTarget.date ?? .distantPast
                        newTempTargetRunStored.endDate = Date()
                        newTempTargetRunStored.target = canceledTempTarget.target ?? 0
                        newTempTargetRunStored.tempTarget = canceledTempTarget
                        newTempTargetRunStored.isUploadedToNS = false
                    }
                }

                // Disable all temporary targets except the one with given id
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
            }
        } catch {
            debug(
                .default,
                "\(DebuggingIdentifiers.failed) Failed to disable active temp targets: \(error)"
            )
        }
    }

    /// Duplicates the current preset and cancels the previous one.
    @MainActor func duplicateTempTargetPresetAndCancelPreviousTempTarget() async {
        // We get the current active Preset by using currentActiveTempTarget which can either be a Preset or a custom TempTarget
        guard let tempTargetPresetToDuplicate = currentActiveTempTarget,
              tempTargetPresetToDuplicate.isPreset == true else { return }

        // Copy the current TempTarget-Preset to not edit the underlying Preset
        let duplidateId = await tempTargetStorage.copyRunningTempTarget(tempTargetPresetToDuplicate)

        // Cancel the duplicated Temp Target
        // As we are on the Main Thread already we don't need to cancel via the objectID in this case
        do {
            try await viewContext.perform {
                tempTargetPresetToDuplicate.enabled = false

                guard self.viewContext.hasChanges else { return }
                try self.viewContext.save()
            }

            if let tempTargetToEdit = try viewContext.existingObject(with: duplidateId) as? TempTargetStored
            {
                currentActiveTempTarget = tempTargetToEdit
                activeTempTargetName = tempTargetToEdit.name ?? String(localized: "Custom Temp Target")
            }
        } catch {
            debugPrint(
                "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to cancel previous override with error: \(error)"
            )
        }
    }

    /// Deletes a Temp Target preset.
    func invokeTempTargetPresetDeletion(_ objectID: NSManagedObjectID) async {
        await tempTargetStorage.deleteTempTargetPreset(objectID)
        setupTempTargetPresetsArray()
        setupScheduledTempTargetsArray()
    }

    /// Resets Temp Target state variables.
    @MainActor func resetTempTargetState() async {
        tempTargetName = ""
        tempTargetTarget = 100
        tempTargetDuration = 0
        percentage = 100
        halfBasalTarget = settingHalfBasalTarget
        date = Date()
    }

    // MARK: - Calculations

    /// Computes the half-basal target based on the current settings.
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

    /// Determines if sensitivity adjustment is enabled based on target.
    func isAdjustSensEnabled(usingTarget initialTarget: Decimal? = nil) -> Bool {
        let target = initialTarget ?? tempTargetTarget
        if target < normalTarget, lowTTlowersSens && autosensMax > 1 { return true }
        if target > normalTarget, highTTraisesSens || isExerciseModeActive { return true }
        return false
    }

    /// Computes the low value for the slider based on the target.
    func computeSliderLow(usingTarget initialTarget: Decimal? = nil) -> Double {
        let calcTarget = initialTarget ?? tempTargetTarget
        guard calcTarget != 0 else { return 15 } // oref defined maximum sensitivity
        let minSens = calcTarget < normalTarget ? 105 : 15
        return Double(max(0, minSens))
    }

    /// Computes the high value for the slider based on the target.
    func computeSliderHigh(usingTarget initialTarget: Decimal? = nil) -> Double {
        let calcTarget = initialTarget ?? tempTargetTarget
        guard calcTarget != 0
        else { return Double(autosensMax * 100) } // oref defined limit for increased insulin delivery
        let maxSens = calcTarget > normalTarget ? 95 : Double(autosensMax * 100)
        return maxSens
    }

    /// Computes the adjusted percentage for the slider.
    func computeAdjustedPercentage(
        usingHBT initialHalfBasalTarget: Decimal? = nil,
        usingTarget initialTarget: Decimal? = nil
    ) -> Double {
        let halfBasalTargetValue = initialHalfBasalTarget ?? halfBasalTarget
        let calcTarget = initialTarget ?? tempTargetTarget
        let deviationFromNormal = halfBasalTargetValue - normalTarget

        let adjustmentFactor = deviationFromNormal + (calcTarget - normalTarget)
        let adjustmentRatio: Decimal = (deviationFromNormal * adjustmentFactor <= 0) ? autosensMax : deviationFromNormal /
            adjustmentFactor

        return Double(min(adjustmentRatio, autosensMax) * 100).rounded()
    }
}

enum TempTargetSensitivityAdjustmentType: String, CaseIterable {
    case standard = "Standard"
    case slider = "Custom"
}
