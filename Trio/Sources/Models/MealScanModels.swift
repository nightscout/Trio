import Foundation

// MARK: - Meal Scan Phase

enum MealScanPhase {
    case camera
    case analyzing
    case chat
    case confirming
}

// MARK: - Detected Food

struct DetectedFood: Identifiable {
    let id: UUID
    let foodId: Int?
    var name: String
    var foodType: String // "Generic" or "Brand"
    var nameSingular: String
    var namePlural: String
    var servingDescription: String
    var portionGrams: Double
    var perUnitGrams: Double
    var carbs: Decimal
    var fat: Decimal
    var protein: Decimal
    var calories: Decimal
    var sugar: Decimal
    var fiber: Decimal
    var alternativeServings: [ServingOption]
    var isRemoved: Bool
    var isUserAdjusted: Bool

    init(
        foodId: Int? = nil,
        name: String,
        foodType: String = "Generic",
        nameSingular: String = "",
        namePlural: String = "",
        servingDescription: String = "",
        portionGrams: Double = 0,
        perUnitGrams: Double = 0,
        carbs: Decimal,
        fat: Decimal,
        protein: Decimal,
        calories: Decimal,
        sugar: Decimal = 0,
        fiber: Decimal = 0,
        alternativeServings: [ServingOption] = []
    ) {
        self.id = UUID()
        self.foodId = foodId
        self.name = name
        self.foodType = foodType
        self.nameSingular = nameSingular
        self.namePlural = namePlural
        self.servingDescription = servingDescription
        self.portionGrams = portionGrams
        self.perUnitGrams = perUnitGrams
        self.carbs = carbs
        self.fat = fat
        self.protein = protein
        self.calories = calories
        self.sugar = sugar
        self.fiber = fiber
        self.alternativeServings = alternativeServings
        self.isRemoved = false
        self.isUserAdjusted = false
    }
}

// MARK: - Serving Option

struct ServingOption: Identifiable {
    let id: String // serving_id from FatSecret
    let description: String
    let metricAmount: Double
    let metricUnit: String
    let numberOfUnits: String
    let isDefault: Bool
    let carbs: Decimal
    let fat: Decimal
    let protein: Decimal
    let calories: Decimal
    let sugar: Decimal
}

// MARK: - Super Bolus Recommendation

enum SuperBolusRecommendation: String {
    case yes
    case consider
    case no
}

// MARK: - Meal Speed

enum MealSpeed: String {
    case fast
    case medium
    case slow
    case mixed
}

// MARK: - Confidence Level

enum ConfidenceLevel: String {
    case high
    case medium
    case low
}

// MARK: - Nutrition Totals

struct NutritionTotals {
    var carbs: Decimal
    var fat: Decimal
    var protein: Decimal
    var calories: Decimal
    var sugar: Decimal
    var fiber: Decimal
    var netCarbs: Decimal
    var fpu: Decimal
    var fpuAbsorptionHours: Decimal
    var speed: MealSpeed
    var confidence: ConfidenceLevel
    var superBolusRecommendation: SuperBolusRecommendation
    var superBolusReason: String

    static var zero: NutritionTotals {
        NutritionTotals(
            carbs: 0, fat: 0, protein: 0, calories: 0,
            sugar: 0, fiber: 0, netCarbs: 0,
            fpu: 0, fpuAbsorptionHours: 0,
            speed: .medium, confidence: .medium,
            superBolusRecommendation: .no, superBolusReason: ""
        )
    }

    static func from(_ foods: [DetectedFood]) -> NutritionTotals {
        let activeFoods = foods.filter { !$0.isRemoved }
        return NutritionTotals(
            carbs: activeFoods.reduce(0) { $0 + $1.carbs },
            fat: activeFoods.reduce(0) { $0 + $1.fat },
            protein: activeFoods.reduce(0) { $0 + $1.protein },
            calories: activeFoods.reduce(0) { $0 + $1.calories },
            sugar: activeFoods.reduce(0) { $0 + $1.sugar },
            fiber: activeFoods.reduce(0) { $0 + $1.fiber },
            netCarbs: activeFoods.reduce(0) { $0 + $1.carbs - $1.fiber },
            fpu: 0, fpuAbsorptionHours: 0,
            speed: .medium, confidence: .medium,
            superBolusRecommendation: .no, superBolusReason: ""
        )
    }
}

// MARK: - Chat Message

enum ChatRole: String {
    case user
    case assistant
}

struct ChatMessage: Identifiable {
    let id: UUID
    let role: ChatRole
    var text: String
    let timestamp: Date
    var updatedTotals: NutritionTotals?

    init(role: ChatRole, text: String, updatedTotals: NutritionTotals? = nil) {
        self.id = UUID()
        self.role = role
        self.text = text
        self.timestamp = Date()
        self.updatedTotals = updatedTotals
    }
}
