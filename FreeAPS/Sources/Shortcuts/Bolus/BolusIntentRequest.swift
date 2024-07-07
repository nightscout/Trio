import Combine
import CoreData
import Foundation

@available(iOS 16.0,*) final class BolusIntentRequest: BaseIntentsRequest {
    private var suggestion: Suggestion? {
        fileStorage.retrieve(OpenAPS.Enact.suggested, as: Suggestion.self)
    }

    func bolus(_ bolusAmount: Double) throws -> LocalizedStringResource {
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
                    "The bolus cannot be larger than the pump setting max bolus.",
                    table: "ShortcutsDetail"
                )
            } else {
                bolusQuantity = apsManager.roundBolus(amount: Decimal(bolusAmount))
            }

        // Block any bolus attempted if it is larger than the max bolus in settings
        case .limitInsulinSuggestion:
            let insulinSuggestion = suggestion?.insulinForManualBolus ?? 0
            if Decimal(bolusAmount) > insulinSuggestion {
                return LocalizedStringResource(
                    "The bolus cannot be larger than the suggested insulin.",
                    table: "ShortcutsDetail"
                )
            } else {
                bolusQuantity = apsManager
                    .roundBolus(amount: Decimal(bolusAmount))
            }
        }

        apsManager.enactBolus(amount: Double(bolusQuantity), isSMB: false)
        return LocalizedStringResource(
            "A bolus command of \(bolusQuantity.formatted()) U of insulin was sent",
            table: "ShortcutsDetail"
        )
    }

    func getLastBG() throws -> String? {
        let glucose = glucoseStorage.recent()
        guard let lastGlucose = glucose.last, let glucoseValue = lastGlucose.glucose else { return nil }
        let units = settingsManager.settings.units

        let glucoseNumber = units == .mmolL ? glucoseValue.asMmolL : Decimal(glucoseValue)
        let formattedString = glucoseFormatter.string(from: Double(glucoseNumber) as NSNumber) ?? "0.0"

        return formattedString + " " + units.rawValue
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
