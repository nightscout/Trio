import Foundation

extension TrioRemoteControl {
    internal func handleBolusCommand(_ pushMessage: PushMessage) async throws {
        guard let bolusAmount = pushMessage.bolusAmount else {
            await logError("Command rejected: bolus amount is missing or invalid.", pushMessage: pushMessage)
            return
        }

        let maxBolus = await TrioApp.resolver.resolve(SettingsManager.self)?.pumpSettings.maxBolus ?? Decimal(0)

        if bolusAmount > maxBolus {
            await logError(
                "Command rejected: bolus amount (\(bolusAmount) units) exceeds the maximum allowed (\(maxBolus) units).",
                pushMessage: pushMessage
            )
            return
        }

        let maxIOB = settings.preferences.maxIOB
        let currentIOB = try await fetchCurrentIOB()
        if (currentIOB + bolusAmount) > maxIOB {
            await logError(
                "Command rejected: bolus amount (\(bolusAmount) units) would exceed max IOB (\(maxIOB) units). Current IOB: \(currentIOB) units.",
                pushMessage: pushMessage
            )
            return
        }

        let totalRecentBolusAmount =
            try await fetchTotalRecentBolusAmount(since: Date(timeIntervalSince1970: pushMessage.timestamp))

        if totalRecentBolusAmount >= bolusAmount * 0.2 {
            await logError(
                "Command rejected: boluses totaling more than 20% of the requested amount have been delivered since the command was sent.",
                pushMessage: pushMessage
            )
            return
        }

        debug(.remoteControl, "Enacting bolus command with amount: \(bolusAmount) units.")

        guard let apsManager = await TrioApp.resolver.resolve(APSManager.self) else {
            await logError(
                "Error: unable to process bolus command because the APS Manager is not available.",
                pushMessage: pushMessage
            )
            return
        }

        await apsManager.enactBolus(amount: Double(truncating: bolusAmount as NSNumber), isSMB: false, callback: nil)

        debug(
            .remoteControl,
            "Remote command processed successfully. \(pushMessage.humanReadableDescription())"
        )
    }

    private func fetchCurrentIOB() async throws -> Decimal {
        let predicate = NSPredicate.predicateFor30MinAgoForDetermination

        let determinations = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: OrefDetermination.self,
            onContext: pumpHistoryFetchContext,
            predicate: predicate,
            key: "timestamp",
            ascending: false,
            fetchLimit: 1,
            propertiesToFetch: ["iob"]
        )

        guard let fetchedResults = determinations as? [[String: Any]],
              let firstResult = fetchedResults.first,
              let iob = firstResult["iob"] as? Decimal
        else {
            await logError("Failed to fetch current IOB.")
            throw CoreDataError.fetchError(function: #function, file: #file)
        }

        return iob
    }

    private func fetchTotalRecentBolusAmount(since date: Date) async throws -> Decimal {
        let predicate = NSPredicate(
            format: "type == %@ AND timestamp > %@",
            PumpEventStored.EventType.bolus.rawValue,
            date as NSDate
        )

        let results: Any = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: PumpEventStored.self,
            onContext: pumpHistoryFetchContext,
            predicate: predicate,
            key: "timestamp",
            ascending: true,
            fetchLimit: nil,
            propertiesToFetch: ["bolus.amount"]
        )

        guard let bolusDictionaries = results as? [[String: Any]] else {
            await logError("Failed to cast fetched bolus events. Fetched entities type: \(type(of: results))")
            throw CoreDataError.fetchError(function: #function, file: #file)
        }

        let totalAmount = bolusDictionaries.compactMap { ($0["bolus.amount"] as? NSNumber)?.decimalValue }.reduce(0, +)

        return totalAmount
    }
}
