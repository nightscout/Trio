import Combine
import CoreData
import Foundation

@available(iOS 16.0,*) final class BolusIntentRequest: BaseIntentsRequest {
    private var suggestion: Determination? {
        // TODO: CRITICAL
        /// This MUST update to use the latest determination's insulinRequired from Core Data
        fileStorage.retrieve(OpenAPS.Enact.suggested, as: Determination.self)
    }

    func bolus(_ bolusAmount: Double) async throws -> LocalizedStringResource {
        var bolusQuantity: Decimal = 0
        switch settingsManager.settings.bolusShortcut {
        // Block boluses if they are disabled
        case .notAllowed:
            return LocalizedStringResource(
                "Bolusing is not allowed with shortcuts.",
                table: "ShortcutsDetail"
            )

        // Block any bolus attempted if it is larger than the max bolus in settings
        case .limitBolusMax:
            if Decimal(bolusAmount) > settingsManager.pumpSettings.maxBolus {
                return LocalizedStringResource(
                    "The bolus cannot be larger than the pump setting max bolus (\(settingsManager.pumpSettings.maxBolus.description)).",
                    table: "ShortcutsDetail"
                )
            } else {
                bolusQuantity = apsManager.roundBolus(amount: Decimal(bolusAmount))
            }

        // Block any bolus attempted if it is larger than the insulin recommended
        case .limitInsulinSuggestion:
            /*
             case .limitInsulinSuggestion:
                 let lastDetermination = await CoreDataStack.shared.fetchEntitiesAsync(
                     ofType: OrefDetermination.self,
                     onContext: coredataContext,
                     predicate: NSPredicate.predicateFor30MinAgoForDetermination,
                     key: "deliveryAt", ascending: false,
                     fetchLimit: 1
                 )
                 guard let latest = lastDetermination.first else {
                     return LocalizedStringResource(
                         "Error retrieving suggested insulin amount guardrail.",
                         table: "ShortcutsDetail"
                     )
                 }
                 let insulinSuggestion = latest.insulinForManualBolus ?? 0
             */
            let insulinSuggestion = suggestion?.insulinForManualBolus ?? 0
            if Decimal(bolusAmount) > insulinSuggestion {
                return LocalizedStringResource(
                    "The bolus cannot be larger than the suggested insulin (\(insulinSuggestion.description)).",
                    table: "ShortcutsDetail"
                )
            }
            // Also make sure that no matter what, the bolus doesn't exceed the max setting in Trio
            else if Decimal(bolusAmount) > settingsManager.pumpSettings.maxBolus {
                return LocalizedStringResource(
                    "The bolus cannot be larger than the pump setting max bolus (\(settingsManager.pumpSettings.maxBolus.description)).",
                    table: "ShortcutsDetail"
                )
            } else {
                bolusQuantity = apsManager
                    .roundBolus(amount: Decimal(bolusAmount))
            }
        }

        await apsManager.enactBolus(amount: Double(bolusQuantity), isSMB: false)
        return LocalizedStringResource(
            "A bolus command of \(bolusQuantity.formatted()) U of insulin was sent",
            table: "ShortcutsDetail"
        )
    }

    private var glucoseFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        if settingsManager.settings.units == .mmolL {
            formatter.minimumFractionDigits = 1
            formatter.maximumFractionDigits = 1
        }
        formatter.roundingMode = .halfUp
        return formatter
    }
}
