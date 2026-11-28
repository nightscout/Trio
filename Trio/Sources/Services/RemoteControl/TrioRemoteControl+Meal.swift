import Foundation

extension TrioRemoteControl {
    static let remoteMealNote = "📡"

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

        if let bolusAmount = payload.bolusAmount, let rejection = bolusLimitRejection(bolusAmount: bolusAmount) {
            await logError(rejection, payload: payload)
            return
        }

        if let rejection = try await treatmentGuardRejection(
            for: payload,
            bolusAmount: payload.bolusAmount,
            checkCarbs: true
        ) {
            await logError(rejection, payload: payload)
            return
        }

        let actualDate = payload.scheduledTime.map { Date(timeIntervalSince1970: $0) }

        let mealEntry = CarbsEntry(
            id: UUID().uuidString, createdAt: Date(), actualDate: actualDate,
            carbs: carbsDecimal ?? 0, fat: fatDecimal ?? 0, protein: proteinDecimal ?? 0,
            note: Self.remoteMealNote, enteredBy: CarbsEntry.local, isFPU: false,
            fpuID: fatDecimal ?? 0 > 0 || proteinDecimal ?? 0 > 0 ? UUID().uuidString : nil
        )

        try await carbsStorage.storeCarbs([mealEntry], areFetchedFromRemote: false)

        if let bolusAmount = payload.bolusAmount {
            await enactRemoteBolus(payload, bolusAmount: bolusAmount, carbsStored: true)
            return
        }

        await logSuccess(
            "Remote command processed successfully. \(payload.humanReadableDescription())",
            payload: payload,
            customNotificationMessage: "Meal logged"
        )
    }
}
