import CoreData
import Foundation

@available(iOS 16.0,*) final class CarbPresetIntentRequest: BaseIntentsRequest {
    func addCarbs(
        _ quantityCarbs: Double,
        _ quantityFat: Double,
        _ quantityProtein: Double,
        _ dateAdded: Date,
        _ note: String?
    ) async throws -> String {
        guard quantityCarbs >= 0.0 || quantityFat >= 0.0 || quantityProtein >= 0.0 else {
            return "not adding carbs in Trio"
        }

        let carbs = min(Decimal(quantityCarbs), settingsManager.settings.maxCarbs)

        try await carbsStorage.storeCarbs(
            [CarbsEntry(
                id: UUID().uuidString,
                createdAt: dateAdded,
                actualDate: dateAdded,
                carbs: carbs,
                fat: Decimal(quantityFat),
                protein: Decimal(quantityProtein),
                note: (note?.isEmpty ?? true) ? "Via Shortcut" : note!,
                enteredBy: CarbsEntry.local,
                isFPU: false, fpuID: nil
            )],
            areFetchedFromRemote: false
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
