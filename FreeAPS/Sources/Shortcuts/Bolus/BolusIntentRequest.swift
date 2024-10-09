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
        case .notAllowed:
            return LocalizedStringResource(
                "the bolus is not allowed with shortcuts",
                table: "ShortcutsDetail"
            )
        case .limitBolusMax:
            bolusQuantity = apsManager
                .roundBolus(amount: min(settingsManager.pumpSettings.maxBolus, Decimal(bolusAmount)))
        case .limitInsulinSuggestion:
            let insulinSuggestion = suggestion?.insulinForManualBolus ?? 0

            bolusQuantity = apsManager
                .roundBolus(amount: min(
                    insulinSuggestion * (settingsManager.settings.insulinReqPercentage / 100),
                    Decimal(bolusAmount)
                ))
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
