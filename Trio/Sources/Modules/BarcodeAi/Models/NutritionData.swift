import Foundation

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

        /// Converts scanned nutrition data to an OpenFoodFactsProduct for consistency
        func toProduct(name: String = "Scanned Label") -> OpenFoodFactsProduct {
            OpenFoodFactsProduct(
                barcode: "manual-\(UUID().uuidString)",
                name: name,
                brand: nil,
                quantity: servingSize,
                servingSize: servingSize,
                ingredients: nil,
                imageURL: nil,
                defaultPortionIsMl: false,
                servingQuantity: servingSizeGrams,
                servingQuantityUnit: "g",
                nutriments: .init(
                    basis: .per100g,
                    energyKcalPer100g: calories,
                    carbohydratesPer100g: carbohydrates,
                    sugarsPer100g: sugars,
                    fatPer100g: fat,
                    proteinPer100g: protein,
                    fiberPer100g: fiber
                )
            )
        }
    }
}
