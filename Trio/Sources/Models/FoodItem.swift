import Foundation
import SwiftUI
import UIKit

// MARK: - Food Item Model

protocol MealNutritionItem {
    var name: String { get }
    var amount: Double { get }
    var isMlInput: Bool { get }
    var nutriments: FoodItem.Nutriments { get }
}

struct FoodItem: Identifiable, Equatable {
    // MARK: - Subtypes

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

    enum ImageSource: Equatable {
        case url(URL)
        case image(UIImage)
        case none

        static func == (lhs: ImageSource, rhs: ImageSource) -> Bool {
            switch (lhs, rhs) {
            case let (.url(u1), .url(u2)): return u1 == u2
            case let (.image(i1), .image(i2)): return i1 === i2
            case (.none, .none): return true
            default: return false
            }
        }
    }

    // MARK: - Properties

    let id: UUID
    let barcode: String?
    let name: String
    let brand: String?
    let quantity: String?

    /// Preferred unit for user input (true = ml, false = g)
    let defaultPortionIsMl: Bool
    var servingQuantity: Double?
    var servingQuantityUnit: String?

    var nutriments: Nutriments

    // User-editable state
    var amount: Double
    var isMlInput: Bool
    var imageSource: ImageSource

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        barcode: String? = nil,
        name: String,
        brand: String? = nil,
        quantity: String? = nil,
        imageSource: ImageSource = .none,
        defaultPortionIsMl: Bool = false,
        servingQuantity: Double? = nil,
        servingQuantityUnit: String? = nil,
        nutriments: Nutriments,
        amount: Double = 0,
        isMlInput: Bool = false
    ) {
        self.id = id
        self.barcode = barcode
        self.name = name
        self.brand = brand
        self.quantity = quantity
        self.imageSource = imageSource
        self.defaultPortionIsMl = defaultPortionIsMl
        self.servingQuantity = servingQuantity
        self.servingQuantityUnit = servingQuantityUnit
        self.nutriments = nutriments
        self.amount = amount
        self.isMlInput = isMlInput
    }
}

extension FoodItem: MealNutritionItem {}

extension Sequence where Element: MealNutritionItem {
    var totalCarbohydrates: Double {
        total(\.carbohydratesPer100g)
    }

    var totalFat: Double {
        total(\.fatPer100g)
    }

    var totalProtein: Double {
        total(\.proteinPer100g)
    }

    private func total(_ keyPath: KeyPath<FoodItem.Nutriments, Double?>) -> Double {
        reduce(into: 0.0) { result, item in
            let amount = item.amount.isFinite ? item.amount : 0
            result += ((item.nutriments[keyPath: keyPath] ?? 0) * amount) / 100.0
        }
    }
}
