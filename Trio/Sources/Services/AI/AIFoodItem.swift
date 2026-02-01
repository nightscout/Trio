import Foundation

/// Represents a single food item detected by AI in a food image
struct AIFoodItem: Codable, Identifiable, Equatable {
    /// Unique identifier for this food item
    let id: UUID

    /// Name/description of the food item
    let name: String

    /// Estimated carbohydrates in grams
    let carbs: Double

    /// Emoji representation of the food (optional)
    let emoji: String?

    /// Absorption time category for this specific item
    let absorptionTime: AbsorptionTimeCategory

    init(id: UUID = UUID(), name: String, carbs: Double, emoji: String? = nil, absorptionTime: AbsorptionTimeCategory = .medium) {
        self.id = id
        self.name = name
        self.carbs = carbs
        self.emoji = emoji
        self.absorptionTime = absorptionTime
    }
}

/// Response from OpenAI containing multiple food items detected in an image
struct AIFoodItemsResponse: Codable, Equatable {
    /// Array of food items detected in the image
    let foodItems: [AIFoodItem]

    /// Overall confidence in the analysis (0.0-1.0)
    let overallConfidence: Double

    /// Total carbs across all items
    var totalCarbs: Double {
        foodItems.reduce(0) { $0 + $1.carbs }
    }

    /// Returns the dominant absorption time based on carb-weighted average
    var dominantAbsorptionTime: AbsorptionTimeCategory {
        guard !foodItems.isEmpty else { return .medium }

        // Weight absorption times by carb content
        var fastCarbs: Double = 0
        var mediumCarbs: Double = 0
        var slowCarbs: Double = 0
        var otherCarbs: Double = 0

        for item in foodItems {
            switch item.absorptionTime {
            case .fast: fastCarbs += item.carbs
            case .medium: mediumCarbs += item.carbs
            case .slow: slowCarbs += item.carbs
            case .other: otherCarbs += item.carbs
            }
        }

        let maxCarbs = max(fastCarbs, mediumCarbs, slowCarbs, otherCarbs)

        if maxCarbs == slowCarbs { return .slow }
        if maxCarbs == fastCarbs { return .fast }
        if maxCarbs == otherCarbs { return .other }
        return .medium
    }
}

/// Represents the selection state for food items, used by the view model
struct FoodItemSelection: Equatable {
    /// The AI response containing all food items
    let response: AIFoodItemsResponse

    /// Set of selected item IDs
    var selectedItemIds: Set<UUID>

    init(response: AIFoodItemsResponse) {
        self.response = response
        // Select all items by default
        selectedItemIds = Set(response.foodItems.map(\.id))
    }

    /// Returns only the selected food items
    var selectedItems: [AIFoodItem] {
        response.foodItems.filter { selectedItemIds.contains($0.id) }
    }

    /// Total carbs for selected items only
    var selectedCarbs: Double {
        selectedItems.reduce(0) { $0 + $1.carbs }
    }

    /// Returns the dominant absorption time for selected items only
    var selectedAbsorptionTime: AbsorptionTimeCategory {
        guard !selectedItems.isEmpty else { return .medium }

        var fastCarbs: Double = 0
        var mediumCarbs: Double = 0
        var slowCarbs: Double = 0
        var otherCarbs: Double = 0

        for item in selectedItems {
            switch item.absorptionTime {
            case .fast: fastCarbs += item.carbs
            case .medium: mediumCarbs += item.carbs
            case .slow: slowCarbs += item.carbs
            case .other: otherCarbs += item.carbs
            }
        }

        let maxCarbs = max(fastCarbs, mediumCarbs, slowCarbs, otherCarbs)

        if maxCarbs == slowCarbs { return .slow }
        if maxCarbs == fastCarbs { return .fast }
        if maxCarbs == otherCarbs { return .other }
        return .medium
    }

    /// Number of selected items
    var selectedCount: Int {
        selectedItemIds.count
    }

    /// The main item to display when collapsed (highest carb item among selected)
    var mainItem: AIFoodItem? {
        selectedItems.max(by: { $0.carbs < $1.carbs })
    }

    /// Summary text for collapsed state (e.g., "Sandwich + 2 others")
    var collapsedSummary: String {
        guard let main = mainItem else {
            return NSLocalizedString("No items selected", comment: "Text shown when no food items are selected")
        }

        let emoji = main.emoji ?? ""
        let name = main.name

        if selectedCount == 1 {
            return "\(emoji) \(name)"
        } else {
            let othersCount = selectedCount - 1
            // Truncate the name if needed to fit within display limits
            let maxNameLength = 12
            let truncatedName = name.count > maxNameLength ? String(name.prefix(maxNameLength)) + "…" : name
            let format = NSLocalizedString(
                "%@%@ +%d",
                comment: "Summary showing main food item and count of others (1: emoji, 2: item name, 3: count of other items)"
            )
            return String(format: format, emoji, truncatedName, othersCount)
        }
    }

    /// Toggle selection state for an item
    mutating func toggleSelection(for itemId: UUID) {
        if selectedItemIds.contains(itemId) {
            selectedItemIds.remove(itemId)
        } else {
            selectedItemIds.insert(itemId)
        }
    }

    /// Check if a specific item is selected
    func isSelected(_ itemId: UUID) -> Bool {
        selectedItemIds.contains(itemId)
    }

    /// Returns true if any items were deselected from the original AI response
    var userModifiedSelection: Bool {
        selectedItemIds.count != response.foodItems.count
    }
}

// MARK: - Extended Response Types for Conversation

/// Response from OpenAI for initial food analysis (includes reasoning)
struct AIFoodItemsResponseWithReasoning: Codable, Equatable {
    /// Array of food items detected in the image
    let foodItems: [AIFoodItem]

    /// Overall confidence in the analysis (0.0-1.0)
    let overallConfidence: Double

    /// Reasoning explaining why these carb values were assigned
    let reasoning: String

    /// Total carbs across all items
    var totalCarbs: Double {
        foodItems.reduce(0) { $0 + $1.carbs }
    }

    /// Convert to basic response (without reasoning)
    var asBasicResponse: AIFoodItemsResponse {
        AIFoodItemsResponse(foodItems: foodItems, overallConfidence: overallConfidence)
    }
}

/// Response from OpenAI for a single item update (inline editing)
struct AISingleItemUpdateResponse: Codable, Equatable {
    /// The updated item ID
    let itemId: UUID

    /// The new carb count for this item
    let updatedCarbs: Double

    /// Brief reasoning for the update
    let reasoning: String

    /// Optional: new absorption time if it changed
    let updatedAbsorptionTime: AbsorptionTimeCategory?
}

/// Response from OpenAI for a conversation turn
struct AIConversationResponse: Codable, Equatable {
    /// All food items (full list, potentially with updates)
    let foodItems: [AIFoodItem]

    /// IDs of items that were updated in this turn
    let updatedItemIds: [UUID]

    /// Message to display in chat
    let assistantMessage: String

    /// Overall confidence in the updated analysis
    let overallConfidence: Double
}
