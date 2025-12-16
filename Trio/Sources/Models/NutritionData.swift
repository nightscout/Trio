import Foundation
import UIKit

// MARK: - Nutrition Data

extension BarcodeScanner {
    /// Represents extracted nutrition data from a label
    struct NutritionData: Equatable {
        var calories: Double?
        var carbohydrates: Double?
        var sugars: Double?
        var fat: Double?
        var saturatedFat: Double?
        var protein: Double?
        var fiber: Double?
        var sodium: Double?
        var servingSize: String?
        var servingSizeGrams: Double?

        var hasAnyData: Bool {
            calories != nil || carbohydrates != nil || fat != nil || protein != nil
        }

        /// Converts scanned nutrition data to a unified FoodItem
        func toProduct(name: String = "Scanned Label", basisAmount: Double = 100.0, capturedImage: UIImage? = nil) -> FoodItem {
            let factor = basisAmount > 0 ? (100.0 / basisAmount) : 1.0

            var imageSource: FoodItem.ImageSource = .none
            if let image = capturedImage {
                imageSource = .image(image)
            }

            return FoodItem(
                name: name,
                imageSource: imageSource,
                nutriments: .init(
                    basis: .per100g,
                    energyKcalPer100g: calories.map { $0 * factor },
                    carbohydratesPer100g: carbohydrates.map { $0 * factor },
                    sugarsPer100g: sugars.map { $0 * factor },
                    fatPer100g: fat.map { $0 * factor },
                    proteinPer100g: protein.map { $0 * factor },
                    fiberPer100g: fiber.map { $0 * factor }
                ),
                amount: servingSizeGrams ?? 100,
                isManualEntry: true
            )
        }
    }
}
