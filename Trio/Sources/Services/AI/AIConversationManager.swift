import Combine
import Foundation
import os.log

/// Manages the state of an AI conversation for food analysis refinement
final class AIConversationManager: ObservableObject {
    private let log = OSLog(subsystem: "com.loopkit.Loop", category: "AIConversationManager")

    // MARK: - Published State

    /// All messages in the conversation
    @Published var messages: [AIConversationMessage] = []

    /// Current food items (source of truth during conversation)
    @Published var currentItems: [AIFoodItem] = []

    /// IDs of items currently being recalculated (for shimmer animation)
    @Published var pendingItemIds: Set<UUID> = []

    /// Whether an API call is in progress
    @Published var isProcessing = false

    /// Error message if last operation failed
    @Published var errorMessage: String?

    // MARK: - Stored Data

    /// The original image data for API calls
    var imageData: Data?

    /// User's initial description (optional context)
    var userDescription: String?

    /// Reasoning from the initial analysis (shown as first chat message)
    var initialReasoning: String?

    /// Selected item IDs (which items are checked in the tree)
    var selectedItemIds: Set<UUID> = []

    /// Overall confidence from the most recent analysis
    var overallConfidence: Double = 0.0

    // MARK: - Computed Properties

    /// Total carbs for selected items
    var selectedCarbs: Double {
        currentItems.filter { selectedItemIds.contains($0.id) }
            .reduce(0) { $0 + $1.carbs }
    }

    /// Total carbs for all items
    var totalCarbs: Double {
        currentItems.reduce(0) { $0 + $1.carbs }
    }

    /// Only the selected items
    var selectedItems: [AIFoodItem] {
        currentItems.filter { selectedItemIds.contains($0.id) }
    }

    // MARK: - Initialization

    init() {}

    /// Initialize with the result of an initial food analysis
    @MainActor func initialize(
        with response: AIFoodItemsResponseWithReasoning,
        imageData: Data,
        userDescription: String?
    ) {
        self.imageData = imageData
        self.userDescription = userDescription
        currentItems = response.foodItems
        selectedItemIds = Set(response.foodItems.map(\.id))
        initialReasoning = response.reasoning
        overallConfidence = response.overallConfidence

        // Add the initial reasoning as the first assistant message (hidden until chat opens)
        messages = [
            .assistantMessage(response.reasoning),
            .carbSummary(items: response.foodItems, canAccept: true)
        ]

        os_log(
            "Initialized conversation with %d items, total %.1fg carbs",
            log: log,
            type: .info,
            currentItems.count,
            totalCarbs
        )
    }

    // MARK: - Inline Item Editing

    /// Update a single item's description and recalculate its carbs
    /// - Parameters:
    ///   - itemId: The ID of the item to update
    ///   - newDescription: The new description for the item
    @MainActor func updateItemDescription(itemId: UUID, newDescription: String) async {
        guard let imageData = imageData else {
            os_log("Cannot update item: no image data", log: log, type: .error)
            return
        }

        guard let itemIndex = currentItems.firstIndex(where: { $0.id == itemId }) else {
            os_log("Cannot update item: item not found", log: log, type: .error)
            return
        }

        let oldName = currentItems[itemIndex].name

        // Immediately update the item name so the UI doesn't revert
        let oldItem = currentItems[itemIndex]
        currentItems[itemIndex] = AIFoodItem(
            id: oldItem.id,
            name: newDescription,
            carbs: oldItem.carbs,
            emoji: oldItem.emoji,
            absorptionTime: oldItem.absorptionTime
        )

        // Add system event to conversation history
        let editEvent = "User updated '\(oldName)' to '\(newDescription)'"
        messages.append(.systemEvent(editEvent))

        // Mark item as pending (triggers shimmer animation)
        pendingItemIds.insert(itemId)
        isProcessing = true
        errorMessage = nil

        os_log(
            "Updating item '%{public}@' to '%{public}@'",
            log: log,
            type: .info,
            oldName,
            newDescription
        )

        do {
            let response = try await OpenAIService.shared.updateSingleItem(
                imageData: imageData,
                currentItems: currentItems,
                editedItemId: itemId,
                newDescription: newDescription
            )

            // Update the item in our list
            var updatedItem = currentItems[itemIndex]
            updatedItem = AIFoodItem(
                id: updatedItem.id,
                name: newDescription,
                carbs: response.updatedCarbs,
                emoji: updatedItem.emoji,
                absorptionTime: response.updatedAbsorptionTime ?? updatedItem.absorptionTime
            )
            currentItems[itemIndex] = updatedItem

            // Add brief reasoning to conversation
            if !response.reasoning.isEmpty {
                messages.append(.assistantMessage(response.reasoning))
            }

            // Add updated carb summary
            messages.append(.carbSummary(items: currentItems, canAccept: true))

            os_log("Item updated: %.1fg carbs", log: log, type: .info, response.updatedCarbs)

        } catch {
            os_log(
                "Failed to update item: %{public}@",
                log: log,
                type: .error,
                error.localizedDescription
            )
            errorMessage = error.localizedDescription
        }

        // Clear pending state
        pendingItemIds.remove(itemId)
        isProcessing = false
    }

    // MARK: - Chat Messages

    /// Send a user message and get AI response
    /// - Parameter text: The user's message
    @MainActor func sendMessage(_ text: String) async {
        guard let imageData = imageData else {
            os_log("Cannot send message: no image data", log: log, type: .error)
            return
        }

        // Add user message to history
        messages.append(.userMessage(text))

        // Mark all items as potentially pending during conversation turn
        let allItemIds = Set(currentItems.map(\.id))
        pendingItemIds = allItemIds
        isProcessing = true
        errorMessage = nil

        os_log("Sending chat message: %{public}@", log: log, type: .info, text)

        do {
            let response = try await OpenAIService.shared.conversationTurn(
                imageData: imageData,
                currentItems: currentItems,
                conversationHistory: messages,
                userMessage: text
            )

            // Update items
            currentItems = response.foodItems
            overallConfidence = response.overallConfidence

            // Update selected IDs to include any new items
            let newItemIds = Set(response.foodItems.map(\.id))
            selectedItemIds = selectedItemIds.intersection(newItemIds).union(
                newItemIds.subtracting(Set(currentItems.map(\.id)))
            )

            // Add assistant response
            messages.append(.assistantMessage(response.assistantMessage))
            messages.append(.carbSummary(items: response.foodItems, canAccept: true))

            os_log(
                "Conversation turn complete: %d items updated",
                log: log,
                type: .info,
                response.updatedItemIds.count
            )

        } catch {
            os_log(
                "Conversation turn failed: %{public}@",
                log: log,
                type: .error,
                error.localizedDescription
            )
            errorMessage = error.localizedDescription

            // Add error message to chat
            messages.append(.assistantMessage(
                "I'm sorry, I encountered an error processing your request. Please try again."
            ))
        }

        // Clear pending state
        pendingItemIds.removeAll()
        isProcessing = false
    }

    // MARK: - Accept Values

    /// Create a FoodItemSelection from the current conversation state
    /// - Returns: A FoodItemSelection representing the current items and selections
    func acceptCurrentValues() -> FoodItemSelection {
        let response = AIFoodItemsResponse(
            foodItems: currentItems,
            overallConfidence: overallConfidence
        )
        var selection = FoodItemSelection(response: response)
        selection.selectedItemIds = selectedItemIds
        return selection
    }

    // MARK: - Selection Management

    /// Toggle selection of an item
    func toggleSelection(for itemId: UUID) {
        if selectedItemIds.contains(itemId) {
            selectedItemIds.remove(itemId)
        } else {
            selectedItemIds.insert(itemId)
        }
    }

    /// Check if an item is selected
    func isSelected(_ itemId: UUID) -> Bool {
        selectedItemIds.contains(itemId)
    }

    // MARK: - Utilities

    /// Clear any error message
    func clearError() {
        errorMessage = nil
    }

    /// Reset the conversation (but keep items)
    func resetConversation() {
        messages = []
        if let reasoning = initialReasoning {
            messages.append(.assistantMessage(reasoning))
        }
        messages.append(.carbSummary(items: currentItems, canAccept: true))
        errorMessage = nil
    }
}
