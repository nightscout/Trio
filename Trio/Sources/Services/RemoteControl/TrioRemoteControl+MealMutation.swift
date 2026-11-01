import CoreData
import Foundation

extension TrioRemoteControl {
    /// Scheduled meals may be dated ahead up to this limit.
    static let mealMutationMaxFuture: TimeInterval = 12 * 60 * 60

    /// Meals older than one calendar day cannot be changed remotely; matches the upload window (`Date.oneDayAgo`).
    static func validateMealAge(_ date: Date, now: Date = Date(), label: String = "meal") -> String? {
        if let oldest = Calendar.current.date(byAdding: .day, value: -1, to: now), date < oldest {
            return "Command rejected: the \(label) is older than 24 hours."
        }
        if now.timeIntervalSince(date) < -mealMutationMaxFuture {
            return "Command rejected: the \(label) is more than 12 hours in the future."
        }
        return nil
    }

    static func validateEditMealInput(
        carbs: Int,
        fat: Int,
        protein: Int,
        maxCarbs: Decimal,
        maxFat: Decimal,
        maxProtein: Decimal
    ) -> String? {
        guard carbs >= 0, fat >= 0, protein >= 0 else {
            return "Command rejected: meal amounts cannot be negative."
        }
        guard carbs > 0 || fat > 0 || protein > 0 else {
            return "Command rejected: all meal amounts are zero. Use delete_meal to remove the meal."
        }
        if Decimal(carbs) > maxCarbs {
            return "Command rejected: carbs amount (\(carbs)g) exceeds the maximum allowed (\(maxCarbs)g)."
        }
        if Decimal(fat) > maxFat {
            return "Command rejected: fat amount (\(fat)g) exceeds the maximum allowed (\(maxFat)g)."
        }
        if Decimal(protein) > maxProtein {
            return "Command rejected: protein amount (\(protein)g) exceeds the maximum allowed (\(maxProtein)g)."
        }
        return nil
    }

    /// Carb equivalents are tied to their meal by `fpuID`; a meal with fat or protein and no `fpuID` cannot be changed as one family.
    static func validateMealLink(_ snapshot: MealSnapshot) -> String? {
        guard snapshot.fpuID == nil, snapshot.fat > 0 || snapshot.protein > 0 else { return nil }
        return "Command rejected: this meal's fat/protein entries are not linked and it cannot be changed remotely."
    }

    func handleDeleteMealCommand(_ payload: CommandPayload) async throws {
        guard payload.carbs == nil, payload.fat == nil, payload.protein == nil, payload.scheduledTime == nil,
              payload.bolusAmount == nil, payload.target == nil, payload.duration == nil, payload.overrideName == nil
        else {
            await rejectMealMutation(payload, "Command rejected: delete_meal cannot carry meal, bolus or override values.")
            return
        }
        guard let handle = payload.mealHandle else {
            await rejectMealMutation(payload, "Command rejected: meal_id is missing or not a valid UUID.")
            return
        }
        guard let target = await resolveMealRoot(handle, payload: payload) else { return }
        if let message = Self.validateMealAge(target.snapshot.date) ?? Self.validateMealLink(target.snapshot) {
            await rejectMealMutation(payload, message)
            return
        }

        let failures: [String]
        do {
            failures = try await carbEntryMutationService.deleteMeal(rootObjectID: target.objectID)
        } catch {
            await rejectFailedMutation(payload, handle: handle, error: error)
            return
        }
        await recalculateAfterMealMutation()

        await logSuccess(
            "Remote command processed successfully. \(payload.humanReadableDescription())",
            payload: payload,
            customNotificationMessage: Self.mealMutationMessage("Meal deleted", failures: failures),
            ack: RemoteCommandAck(commandId: payload.commandId, mealId: handle.uuidString, result: .deleted)
        )
    }

    func handleEditMealCommand(_ payload: CommandPayload) async throws {
        guard payload.bolusAmount == nil, payload.target == nil, payload.duration == nil, payload.overrideName == nil else {
            await rejectMealMutation(payload, "Command rejected: edit_meal cannot carry bolus or override values.")
            return
        }
        guard let handle = payload.mealHandle else {
            await rejectMealMutation(payload, "Command rejected: meal_id is missing or not a valid UUID.")
            return
        }
        guard let carbs = payload.carbs, let fat = payload.fat, let protein = payload.protein,
              let scheduledTime = payload.scheduledTime
        else {
            await rejectMealMutation(payload, "Command rejected: edit_meal requires carbs, fat, protein and scheduled_time.")
            return
        }

        let limits = settings.settings
        if let message = Self.validateEditMealInput(
            carbs: carbs,
            fat: fat,
            protein: protein,
            maxCarbs: limits.maxCarbs,
            maxFat: limits.maxFat,
            maxProtein: limits.maxProtein
        ) {
            await rejectMealMutation(payload, message)
            return
        }

        let newDate = Date(timeIntervalSince1970: scheduledTime)
        if let message = Self.validateMealAge(newDate, label: "new meal time") {
            await rejectMealMutation(payload, message)
            return
        }

        guard let target = await resolveMealRoot(handle, payload: payload) else { return }
        guard handle == target.snapshot.id else {
            await rejectMealMutation(payload, "Command rejected: meal_id refers to a carb equivalent, not the meal itself.")
            return
        }
        if let message = Self.validateMealAge(target.snapshot.date) ?? Self.validateMealLink(target.snapshot) {
            await rejectMealMutation(payload, message)
            return
        }

        let note = target.snapshot.note.flatMap { $0.isEmpty ? nil : $0 } ?? Self.remoteMealNote
        let replacement = CarbsEntry(
            id: UUID().uuidString,
            createdAt: Date(),
            actualDate: newDate,
            carbs: Decimal(carbs),
            fat: Decimal(fat),
            protein: Decimal(protein),
            note: note,
            enteredBy: CarbsEntry.local,
            isFPU: false,
            fpuID: fat > 0 || protein > 0 ? UUID().uuidString : nil
        )

        let newID: UUID
        let failures: [String]
        do {
            (newID, failures) = try await carbEntryMutationService.replaceMeal(
                rootObjectID: target.objectID,
                with: replacement
            )
        } catch {
            await rejectFailedMutation(payload, handle: handle, error: error)
            return
        }
        await recalculateAfterMealMutation()

        await logSuccess(
            "Remote command processed successfully. \(payload.humanReadableDescription())",
            payload: payload,
            customNotificationMessage: Self.mealMutationMessage("Meal updated", failures: failures),
            ack: RemoteCommandAck(commandId: payload.commandId, mealId: newID.uuidString, result: .updated)
        )
    }

    private func resolveMealRoot(
        _ handle: UUID,
        payload: CommandPayload
    ) async -> (objectID: NSManagedObjectID, snapshot: MealSnapshot)? {
        do {
            guard let target = try await carbsStorage.fetchMealRoot(handle: handle) else {
                await reportMealNotFound(payload, handle: handle)
                return nil
            }
            return target
        } catch CarbsStorageError.ambiguousMealHandle {
            await rejectMealMutation(payload, "Command rejected: meal_id matches more than one meal.")
            return nil
        } catch {
            await rejectMealMutation(payload, "Command rejected: the meal could not be read: \(error.localizedDescription)")
            return nil
        }
    }

    private func reportMealNotFound(_ payload: CommandPayload, handle: UUID) async {
        await logError(
            "Command rejected: the meal was not found. It may already have been deleted or changed on the phone.",
            payload: payload,
            ack: RemoteCommandAck(commandId: payload.commandId, mealId: handle.uuidString, result: .notFound)
        )
    }

    private func rejectFailedMutation(_ payload: CommandPayload, handle: UUID, error: Error) async {
        if case CarbEntryMutationError.rootNotFound = error {
            await reportMealNotFound(payload, handle: handle)
            return
        }
        await rejectMealMutation(payload, "Command rejected: the meal could not be changed: \(error.localizedDescription)")
    }

    private func rejectMealMutation(_ payload: CommandPayload, _ message: String) async {
        await logError(
            message,
            payload: payload,
            ack: RemoteCommandAck(commandId: payload.commandId, mealId: payload.mealId, result: .rejected)
        )
    }

    /// The meal change is already saved; a failed determination only delays the COB update to the next loop cycle.
    private func recalculateAfterMealMutation() async {
        do {
            try await apsManager.determineBasalSync()
        } catch {
            warning(.remote, "COB recalculation after meal change failed", error: error)
        }
    }

    private static func mealMutationMessage(_ base: String, failures: [String]) -> String {
        guard !failures.isEmpty else { return base }
        return "\(base). \(failures.joined(separator: "; ")); the entry may still show in Nightscout."
    }
}
