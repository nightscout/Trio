import Foundation

// MARK: - OpenFoodFacts Models

extension BarcodeScanner {
    /// Represents a product from OpenFoodFacts API
    struct OpenFoodFactsProduct: Identifiable, Equatable {
        struct Nutriments: Equatable {
            enum Basis: Equatable {
                case per100g
                case per100ml
            }

            var basis: Basis
            var energyKcalPer100g: Double?
            var carbohydratesPer100g: Double?
            var sugarsPer100g: Double?
            var fatPer100g: Double?
            var proteinPer100g: Double?
            var fiberPer100g: Double?
        }

        var id: String { barcode }

        let barcode: String
        let name: String
        let brand: String?
        let quantity: String?
        let servingSize: String?
        let ingredients: String?
        let imageURL: URL?
        /// Preferred unit for user input (true = ml, false = g),
        /// primarily derived from `product_quantity_unit`.
        let defaultPortionIsMl: Bool
        let servingQuantity: Double?
        let servingQuantityUnit: String?
        var nutriments: Nutriments
    }
}

// MARK: - Scanned Product Item

extension BarcodeScanner {
    /// Represents a scanned product with user-entered amount
    struct ScannedProductItem: Identifiable, Equatable {
        let id: UUID
        let product: OpenFoodFactsProduct
        var amount: Double
        var isMlInput: Bool
        let isManualEntry: Bool

        init(product: OpenFoodFactsProduct, amount: Double = 0, isMlInput: Bool = false, isManualEntry: Bool = false) {
            id = UUID()
            self.product = product
            self.amount = amount
            self.isMlInput = isMlInput
            self.isManualEntry = isManualEntry
        }

        static func == (lhs: ScannedProductItem, rhs: ScannedProductItem) -> Bool {
            lhs.id == rhs.id &&
                lhs.product == rhs.product &&
                lhs.amount == rhs.amount &&
                lhs.isMlInput == rhs.isMlInput &&
                lhs.isManualEntry == rhs.isManualEntry
        }
    }
}
