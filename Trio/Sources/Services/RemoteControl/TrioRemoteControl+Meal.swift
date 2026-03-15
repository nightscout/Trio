import Foundation

extension TrioRemoteControl {
    func handleMealCommand(_ payload: CommandPayload) async throws {
        guard payload.carbs != nil || payload.fat != nil || payload.protein != nil else {
            await logError("Command rejected: meal data is incomplete or invalid.", payload: payload)
            return
        }

        let carbsDecimal = payload.carbs != nil ? Decimal(payload.carbs!) : nil
        let fatDecimal = payload.fat != nil ? Decimal(payload.fat!) : nil
        let proteinDecimal = payload.protein != nil ? Decimal(payload.protein!) : nil

        let settings = await TrioApp.resolver.resolve(SettingsManager.self)?.settings
        let maxCarbs = settings?.maxCarbs ?? Decimal(0)
        let maxFat = settings?.maxFat ?? Decimal(0)
        let maxProtein = settings?.maxProtein ?? Decimal(0)

        if let carbs = carbsDecimal, carbs > maxCarbs {
            await logError(
                "Command rejected: carbs amount (\(carbs)g) exceeds the maximum allowed (\(maxCarbs)g).",
                payload: payload
            )
            return
        }
        if let fat = fatDecimal, fat > maxFat {
            await logError("Command rejected: fat amount (\(fat)g) exceeds the maximum allowed (\(maxFat)g).", payload: payload)
            return
        }
        if let protein = proteinDecimal, protein > maxProtein {
            await logError(
                "Command rejected: protein amount (\(protein)g) exceeds the maximum allowed (\(maxProtein)g).",
                payload: payload
            )
            return
        }

        let payloadDate = Date(timeIntervalSince1970: payload.timestamp)
        let taskContext = CoreDataStack.shared.newTaskContext()
        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: CarbEntryStored.self, onContext: taskContext, predicate: NSPredicate(
                format: "date > %@",
                payloadDate as NSDate
            ), key: "date", ascending: false
        )

        await taskContext.perform {
            guard let recentCarbEntries = results as? [CarbEntryStored] else { return }
            if !recentCarbEntries.isEmpty {
                Task {
                    await self.logError(
                        "Command rejected: newer carb entries have been logged since the command was sent.",
                        payload: payload
                    )
                    return
                }
            }
        }

        let actualDate = payload.scheduledTime.map { Date(timeIntervalSince1970: $0) }

        let mealEntry = CarbsEntry(
            id: UUID().uuidString, createdAt: Date(), actualDate: actualDate,
            carbs: carbsDecimal ?? 0, fat: fatDecimal, protein: proteinDecimal,
            note: "Remote meal command", enteredBy: CarbsEntry.local, isFPU: false,
            fpuID: fatDecimal ?? 0 > 0 || proteinDecimal ?? 0 > 0 ? UUID().uuidString : nil
        )

        try await carbsStorage.storeCarbs([mealEntry], areFetchedFromRemote: false)

        if payload.bolusAmount == nil {
            await logSuccess(
                "Remote command processed successfully. \(payload.humanReadableDescription())",
                payload: payload,
                customNotificationMessage: "Meal logged"
            )
        }
    }
}
