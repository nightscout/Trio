import Foundation

extension TrioRemoteControl {
    func handleMealCommand(_ pushMessage: PushMessage) async throws {
        guard pushMessage.carbs != nil || pushMessage.fat != nil || pushMessage.protein != nil else {
            await logError("Command rejected: meal data is incomplete or invalid.", pushMessage: pushMessage)
            return
        }

        let carbsDecimal = pushMessage.carbs != nil ? Decimal(pushMessage.carbs!) : nil
        let fatDecimal = pushMessage.fat != nil ? Decimal(pushMessage.fat!) : nil
        let proteinDecimal = pushMessage.protein != nil ? Decimal(pushMessage.protein!) : nil

        let settings = await TrioApp.resolver.resolve(SettingsManager.self)?.settings
        let maxCarbs = settings?.maxCarbs ?? Decimal(0)
        let maxFat = settings?.maxFat ?? Decimal(0)
        let maxProtein = settings?.maxProtein ?? Decimal(0)

        if let carbs = carbsDecimal, carbs > maxCarbs {
            await logError(
                "Command rejected: carbs amount (\(carbs)g) exceeds the maximum allowed (\(maxCarbs)g).",
                pushMessage: pushMessage
            )
            return
        }

        if let fat = fatDecimal, fat > maxFat {
            await logError(
                "Command rejected: fat amount (\(fat)g) exceeds the maximum allowed (\(maxFat)g).",
                pushMessage: pushMessage
            )
            return
        }

        if let protein = proteinDecimal, protein > maxProtein {
            await logError(
                "Command rejected: protein amount (\(protein)g) exceeds the maximum allowed (\(maxProtein)g).",
                pushMessage: pushMessage
            )
            return
        }

        let pushMessageDate = Date(timeIntervalSince1970: pushMessage.timestamp)
        let taskContext = CoreDataStack.shared.newTaskContext()
        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: CarbEntryStored.self,
            onContext: taskContext,
            predicate: NSPredicate(format: "date > %@", pushMessageDate as NSDate),
            key: "date",
            ascending: false
        )

        await taskContext.perform {
            guard let recentCarbEntries = results as? [CarbEntryStored] else { return }
            if !recentCarbEntries.isEmpty {
                Task {
                    await self.logError(
                        "Command rejected: newer carb entries have been logged since the command was sent.",
                        pushMessage: pushMessage
                    )
                    return
                }
            }
        }

        let actualDate: Date?
        if let scheduledTime = pushMessage.scheduledTime {
            actualDate = Date(timeIntervalSince1970: scheduledTime)
        } else {
            actualDate = nil
        }

        let mealEntry = CarbsEntry(
            id: UUID().uuidString,
            createdAt: Date(),
            actualDate: actualDate,
            carbs: carbsDecimal ?? 0,
            fat: fatDecimal,
            protein: proteinDecimal,
            note: "Remote meal command",
            enteredBy: CarbsEntry.local,
            isFPU: false,
            fpuID: fatDecimal ?? 0 > 0 || proteinDecimal ?? 0 > 0 ? UUID().uuidString : nil
        )

        try await carbsStorage.storeCarbs([mealEntry], areFetchedFromRemote: false)

        debug(
            .remoteControl,
            "Remote command processed successfully. \(pushMessage.humanReadableDescription())"
        )
    }
}
