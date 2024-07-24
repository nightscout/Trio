import Combine
import CoreData
import Foundation

@available(iOS 16.0,*) final class BolusIntentRequest: BaseIntentsRequest {
    private var suggestion: Determination? {
        fileStorage.retrieve(OpenAPS.Enact.suggested, as: Determination.self)
    }

    func bolus(_ bolusAmount: Double) async throws -> LocalizedStringResource {
        var bolusQ: Decimal = 0
        switch settingsManager.settings.bolusShortcut {
        case .noAllowed:
            return LocalizedStringResource(
                "Bolusing is not allowed with Shortcuts",
                table: "ShortcutsDetail"
            )
        case .limitBolusMax:
            bolusQ = apsManager
                .roundBolus(amount: min(settingsManager.pumpSettings.maxBolus, Decimal(bolusAmount)))
        case .limitInsulinSuggestion:
            let insulinSuggestion = suggestion?.insulinForManualBolus ?? 0

            bolusQ = apsManager
                .roundBolus(amount: min(
                    insulinSuggestion * (settingsManager.settings.insulinReqPercentage / 100),
                    Decimal(bolusAmount)
                ))
        }

        await apsManager.enactBolus(amount: Double(bolusQ), isSMB: false)
        return LocalizedStringResource(
            "A bolus command of \(bolusQ.formatted()) U of insulin was sent",
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
