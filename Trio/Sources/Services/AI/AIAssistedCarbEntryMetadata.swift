import Foundation

/// Metadata captured when a carb entry is created using AI-assisted food photo analysis
struct AIAssistedCarbEntryMetadata: Codable, Equatable {
    /// Detailed description of the food as analyzed by AI
    let detailedDescription: String

    /// AI's estimated carbohydrate count in grams (total of all detected items)
    let estimatedCarbs: Double

    /// Emoji representation of the food (1-3 emojis)
    let emoji: String

    /// AI's recommended absorption time category
    let absorptionTime: AbsorptionTimeCategory

    /// Confidence level for the carb estimate (0.0-1.0)
    let carbConfidence: Double

    /// Confidence level for the absorption time estimate (0.0-1.0)
    let absorptionConfidence: Double

    /// Confidence level for the emoji selection (0.0-1.0)
    let emojiConfidence: Double

    /// Whether the user modified the AI-suggested values before submission
    var userModified: Bool

    /// When the AI analysis was performed
    let analyzedAt: Date

    /// Array of individual food items detected (for multi-item analysis)
    let foodItems: [AIFoodItem]?

    /// IDs of items that were selected by the user (nil means all selected or single-item mode)
    let selectedItemIds: [UUID]?

    init(
        detailedDescription: String,
        estimatedCarbs: Double,
        emoji: String,
        absorptionTime: AbsorptionTimeCategory,
        carbConfidence: Double,
        absorptionConfidence: Double,
        emojiConfidence: Double,
        userModified: Bool = false,
        analyzedAt: Date = Date(),
        foodItems: [AIFoodItem]? = nil,
        selectedItemIds: [UUID]? = nil
    ) {
        self.detailedDescription = detailedDescription
        self.estimatedCarbs = estimatedCarbs
        self.emoji = emoji
        self.absorptionTime = absorptionTime
        self.carbConfidence = carbConfidence
        self.absorptionConfidence = absorptionConfidence
        self.emojiConfidence = emojiConfidence
        self.userModified = userModified
        self.analyzedAt = analyzedAt
        self.foodItems = foodItems
        self.selectedItemIds = selectedItemIds
    }

    /// Returns JSON data representation suitable for logging to external services
    var asJSONData: Data? {
        let loggableData = LoggableMetadata(from: self)
        return try? JSONEncoder().encode(loggableData)
    }

    /// Returns JSON string representation suitable for logging
    var asJSONString: String? {
        guard let data = asJSONData else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Returns a formatted string suitable for Nightscout notes field
    var asNightscoutNotes: String {
        var notes = "AI-Assisted Entry"
        if !emoji.isEmpty {
            notes += " \(emoji)"
        }
        notes += " | Est: \(Int(estimatedCarbs))g (conf: \(Int(carbConfidence * 100))%)"

        // Add multi-item breakdown if present
        if let items = foodItems, items.count > 1 {
            let itemCount = items.count
            let selectedCount = selectedItemIds?.count ?? itemCount
            if selectedCount < itemCount {
                notes += " | \(selectedCount)/\(itemCount) items selected"
            } else {
                notes += " | \(itemCount) items"
            }
        }

        notes += " | Absorption: \(absorptionTime.rawValue) (conf: \(Int(absorptionConfidence * 100))%)"
        if userModified {
            notes += " | User modified"
        }
        notes += " | \(detailedDescription)"
        return notes
    }
}

// MARK: - Loggable Data Structures

/// Codable structure for logging AI metadata to external services
struct LoggableMetadata: Codable {
    let detailedDescription: String
    let estimatedCarbs: Double
    let emoji: String
    let absorptionTime: String
    let absorptionTimeHours: Double
    let carbConfidence: Double
    let absorptionConfidence: Double
    let emojiConfidence: Double
    let userModified: Bool
    let analyzedAt: String
    let foodItemCount: Int?
    let selectedItemCount: Int?
    let deselectedItemCount: Int?
    let foodItems: [LoggableFoodItem]?

    init(from metadata: AIAssistedCarbEntryMetadata) {
        detailedDescription = metadata.detailedDescription
        estimatedCarbs = metadata.estimatedCarbs
        emoji = metadata.emoji
        absorptionTime = metadata.absorptionTime.rawValue
        absorptionTimeHours = metadata.absorptionTime.typicalHours
        carbConfidence = metadata.carbConfidence
        absorptionConfidence = metadata.absorptionConfidence
        emojiConfidence = metadata.emojiConfidence
        userModified = metadata.userModified
        analyzedAt = ISO8601DateFormatter().string(from: metadata.analyzedAt)

        if let items = metadata.foodItems {
            foodItemCount = items.count
            foodItems = items.map { LoggableFoodItem(from: $0) }

            if let selectedIds = metadata.selectedItemIds {
                selectedItemCount = selectedIds.count
                deselectedItemCount = items.count - selectedIds.count
            } else {
                selectedItemCount = nil
                deselectedItemCount = nil
            }
        } else {
            foodItemCount = nil
            selectedItemCount = nil
            deselectedItemCount = nil
            foodItems = nil
        }
    }
}

/// Codable structure for logging individual food items
struct LoggableFoodItem: Codable {
    let name: String
    let carbs: Double
    let emoji: String
    let absorptionTime: String

    init(from item: AIFoodItem) {
        name = item.name
        carbs = item.carbs
        emoji = item.emoji ?? ""
        absorptionTime = item.absorptionTime.rawValue
    }
}
