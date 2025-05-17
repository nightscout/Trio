import Combine
import CoreData
import Foundation

@available(iOS 16.0,*) final class BolusIntentRequest: BaseIntentsRequest {
    func bolus(_ bolusAmount: Double) async throws -> LocalizedStringResource {
        var bolusQuantity: Decimal = 0
        switch settingsManager.settings.bolusShortcut {
        // Block boluses if they are disabled
        case .notAllowed:
            return LocalizedStringResource(
                "Bolusing via Shortcuts is disabled in Trio settings."
            )

        // Block any bolus attempted if it is larger than the max bolus in settings
        case .limitBolusMax:
            if Decimal(bolusAmount) > settingsManager.pumpSettings.maxBolus {
                return LocalizedStringResource(
                    "The bolus cannot be larger than the pump setting max bolus (\(settingsManager.pumpSettings.maxBolus.description))."
                )
            } else {
                bolusQuantity = apsManager.roundBolus(amount: Decimal(bolusAmount))
            }
            await apsManager.enactBolus(amount: Double(bolusQuantity), isSMB: false, callback: nil)
            return LocalizedStringResource(
                "A bolus command of \(bolusQuantity.formatted()) U of insulin was sent."
            )
        }
    }
}
