import Foundation
import HealthKit

extension TrioRemoteControl {
    internal func handleBolusCommand(_ payload: CommandPayload) async throws {
        guard let bolusAmount = payload.bolusAmount else {
            await logError("Command rejected: bolus amount is missing or invalid.", payload: payload)
            return
        }

        let maxBolus = await TrioApp.resolver.resolve(SettingsManager.self)?.pumpSettings.maxBolus ?? Decimal(0)

        if bolusAmount > maxBolus {
            await logError(
                "Command rejected: bolus amount (\(bolusAmount) units) exceeds the maximum allowed (\(maxBolus) units).",
                payload: payload
            )
            return
        }

        let maxIOB = settings.preferences.maxIOB
        guard let currentIOB = iobService.currentIOB else {
            throw CoreDataError.fetchError(function: #function, file: #file)
        }
        if (currentIOB + bolusAmount) > maxIOB {
            await logError(
                "Command rejected: bolus amount (\(bolusAmount) units) would exceed max IOB (\(maxIOB) units). Current IOB: \(currentIOB) units.",
                payload: payload
            )
            return
        }

        let totalRecentBolusAmount =
            try await fetchTotalRecentBolusAmount(since: Date(timeIntervalSince1970: payload.timestamp))

        if totalRecentBolusAmount >= bolusAmount * 0.2 {
            await logError(
                "Command rejected: boluses totaling more than 20% of the requested amount have been delivered since the command was sent.",
                payload: payload
            )
            return
        }

        debug(.remoteControl, "Enacting bolus command with amount: \(bolusAmount) units.")

        guard let apsManager = await TrioApp.resolver.resolve(APSManager.self) else {
            await logError(
                "Error: unable to process bolus command because the APS Manager is not available.",
                payload: payload
            )
            return
        }

        if let returnInfo = payload.returnNotification {
            await RemoteNotificationResponseManager.shared.sendResponseNotification(
                to: returnInfo,
                commandType: payload.commandType,
                success: true,
                message: "Initiating bolus..."
            )
        }

        await apsManager
            .enactBolus(amount: Double(truncating: bolusAmount as NSNumber), isSMB: false) { [weak self] success, message in
                guard let self = self else { return }
                Task {
                    if success {
                        await self.logSuccess(
                            "Remote command processed successfully. \(payload.humanReadableDescription())",
                            payload: payload,
                            customNotificationMessage: "Bolus started"
                        )
                    } else {
                        await self.logError(
                            message,
                            payload: payload
                        )
                    }
                }
            }
    }

    private func fetchTotalRecentBolusAmount(since date: Date) async throws -> Decimal {
        let predicate = NSPredicate(
            format: "type == %@ AND timestamp > %@",
            PumpEventStored.EventType.bolus.rawValue,
            date as NSDate
        )
        let results: Any = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: PumpEventStored.self, onContext: pumpHistoryFetchContext, predicate: predicate, key: "timestamp",
            ascending: true, fetchLimit: nil, propertiesToFetch: ["bolus.amount"]
        )
        guard let bolusDictionaries = results as? [[String: Any]] else {
            await logError("Failed to cast fetched bolus events. Fetched entities type: \(type(of: results))")
            throw CoreDataError.fetchError(function: #function, file: #file)
        }
        let totalAmount = bolusDictionaries.compactMap { ($0["bolus.amount"] as? NSNumber)?.decimalValue }.reduce(0, +)
        return totalAmount
    }
}
