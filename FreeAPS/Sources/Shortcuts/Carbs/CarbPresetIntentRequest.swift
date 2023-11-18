import CoreData
import Foundation

@available(iOS 16.0,*) final class CarbPresetIntentRequest: BaseIntentsRequest {
    func addCarbs(_ quantityCarbs: Double, _ quantityFat: Double, _ quantityProtein: Double, _ dateAdded: Date) throws -> String {
        guard quantityCarbs >= 0.0 || quantityFat >= 0.0 || quantityProtein >= 0.0 else {
            return "no adding carbs in iAPS"
        }

        let carbs = min(Decimal(quantityCarbs), settingsManager.settings.maxCarbs)

        carbsStorage.storeCarbs(
            [CarbsEntry(
                id: UUID().uuidString,
                createdAt: dateAdded,
                carbs: carbs,
                fat: Decimal(quantityFat),
                protein: Decimal(quantityProtein),
                note: "add with shortcuts",
                enteredBy: CarbsEntry.manual,
                isFPU: false, fpuID: nil
            )]
        )
        var resultDisplay: String
        resultDisplay = "\(carbs) g carbs"
        if quantityFat > 0.0 {
            resultDisplay = "\(resultDisplay) and \(quantityFat) g fats"
        }
        if quantityProtein > 0.0 {
            resultDisplay = "\(resultDisplay) and \(quantityProtein) g protein"
        }
        let dateName = dateAdded.formatted()
        resultDisplay = "\(resultDisplay) added at \(dateName)"
        return resultDisplay
    }
}
