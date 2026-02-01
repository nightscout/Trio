import LoopKitUI
import SwiftUI

/// A collapsible view for displaying and selecting individual food items from AI analysis
/// Now supports inline editing of item descriptions and shimmer animations during recalculation
struct FoodItemsSelectionView: View {
    @Binding var selection: FoodItemSelection?
    @Binding var isExpanded: Bool

    /// IDs of items currently being recalculated (shows shimmer animation)
    let pendingItemIds: Set<UUID>

    /// Called when user toggles an item's checkbox
    let onToggleItem: (UUID) -> Void

    /// Called when user edits an item's description (itemId, newDescription)
    let onEditItem: ((UUID, String) -> Void)?

    /// Called when user taps "Refine with AI" button
    let onOpenChat: (() -> Void)?

    // State for inline editing
    @State private var editingItemId: UUID?
    @State private var editText: String = ""
    @FocusState private var isEditingFocused: Bool

    // Check if any item is pending (for total shimmer)
    private var isAnyItemPending: Bool {
        !pendingItemIds.isEmpty
    }

    init(
        selection: Binding<FoodItemSelection?>,
        isExpanded: Binding<Bool>,
        pendingItemIds: Set<UUID> = [],
        onToggleItem: @escaping (UUID) -> Void,
        onEditItem: ((UUID, String) -> Void)? = nil,
        onOpenChat: (() -> Void)? = nil
    ) {
        _selection = selection
        _isExpanded = isExpanded
        self.pendingItemIds = pendingItemIds
        self.onToggleItem = onToggleItem
        self.onEditItem = onEditItem
        self.onOpenChat = onOpenChat
    }

    var body: some View {
        if let selection = selection {
            VStack(spacing: 0) {
                // Collapsed header row
                collapsedHeader(selection: selection)

                // Expanded content
                if isExpanded {
                    expandedContent(selection: selection)

                    // Refine with AI button
                    if onOpenChat != nil {
                        refineWithAIButton
                    }
                }
            }
        }
    }

    private func collapsedHeader(selection: FoodItemSelection) -> some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
            }
        }) {
            HStack(spacing: 8) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 16)

                Text(selection.collapsedSummary)
                    .font(.body)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 8)

                // Total carbs with shimmer when any item is pending
                HStack(spacing: 4) {
                    if isAnyItemPending {
                        AnimatedSparkleIcon(isAnimating: true)
                    }
                    Text(formatCarbs(selection.selectedCarbs))
                        .font(.body.monospacedDigit())
                        .foregroundColor(.primary)
                        .fixedSize()
                }
                .padding(.horizontal, isAnyItemPending ? 12 : 0)
                .padding(.vertical, isAnyItemPending ? 6 : 0)
                .background(
                    Group {
                        if isAnyItemPending {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(.secondarySystemFill))
                        }
                    }
                )
                .totalShimmer(isAnimating: isAnyItemPending)
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func expandedContent(selection: FoodItemSelection) -> some View {
        VStack(spacing: 0) {
            ForEach(selection.response.foodItems) { item in
                let isPending = pendingItemIds.contains(item.id)
                let isEditing = editingItemId == item.id

                foodItemRow(
                    item: item,
                    isSelected: selection.isSelected(item.id),
                    isPending: isPending,
                    isEditing: isEditing
                )

                if item.id != selection.response.foodItems.last?.id {
                    Divider()
                        .padding(.leading, 32)
                }
            }
        }
    }

    private func foodItemRow(
        item: AIFoodItem,
        isSelected: Bool,
        isPending: Bool,
        isEditing: Bool
    ) -> some View {
        HStack(spacing: 8) {
            // Checkbox
            Button(action: {
                onToggleItem(item.id)
            }) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                    .frame(width: 24)
            }
            .buttonStyle(.plain)

            // Emoji
            if let emoji = item.emoji, !emoji.isEmpty {
                Text(emoji)
                    .font(.body)
            }

            // Name (editable)
            if isEditing {
                // Editing mode - show text field
                TextField("", text: $editText)
                    .font(.body)
                    .foregroundColor(.primary)
                    .focused($isEditingFocused)
                    .onSubmit {
                        commitEdit(for: item)
                    }
                    .submitLabel(.done)
            } else {
                // Display mode - tappable to edit
                Text(item.name)
                    .font(.body)
                    .foregroundColor(
                        isPending ? Color(hue: 0.75, saturation: 0.5, brightness: 0.7) :
                            (isSelected ? .primary : .secondary)
                    )
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .onTapGesture {
                        if onEditItem != nil, !isPending {
                            startEditing(item: item)
                        }
                    }
            }

            Spacer(minLength: 8)

            // Carbs with shimmer when pending
            HStack(spacing: 4) {
                if isPending {
                    AnimatedSparkleIcon(isAnimating: true)
                }
                Text(formatCarbs(item.carbs))
                    .font(.body.monospacedDigit())
                    .foregroundColor(isSelected ? .primary : .secondary)
                    .fixedSize()
            }
            .padding(.horizontal, isPending ? 10 : 0)
            .padding(.vertical, isPending ? 4 : 0)
            .background(
                Group {
                    if isPending {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(.secondarySystemFill))
                    }
                }
            )
            .shimmer(isAnimating: isPending)
        }
        .padding(.vertical, 8)
        .padding(.leading, 4)
        .padding(.horizontal, isPending ? 4 : 0)
        .background(
            Group {
                if isPending {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(.secondarySystemFill).opacity(0.5))
                }
            }
        )
        .totalShimmer(isAnimating: isPending)
        .contentShape(Rectangle())
        .onTapGesture {
            // If we're editing another item, commit that edit first
            if let editingId = editingItemId, editingId != item.id {
                if let editingItem = selection?.response.foodItems.first(where: { $0.id == editingId }) {
                    commitEdit(for: editingItem)
                }
            }
        }
    }

    private var refineWithAIButton: some View {
        Button(action: {
            // Commit any pending edit before opening chat
            if let editingId = editingItemId,
               let item = selection?.response.foodItems.first(where: { $0.id == editingId })
            {
                commitEdit(for: item)
            }
            onOpenChat?()
        }) {
            HStack(spacing: 6) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 14))
                Text("Refine with AI", comment: "Button to open AI chat for refining food analysis")
                    .font(.subheadline)
            }
            .foregroundColor(.accentColor)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .disabled(isAnyItemPending)
        .opacity(isAnyItemPending ? 0.5 : 1.0)
    }

    // MARK: - Editing Helpers

    private func startEditing(item: AIFoodItem) {
        editingItemId = item.id
        editText = item.name
        isEditingFocused = true
    }

    private func commitEdit(for item: AIFoodItem) {
        let trimmedText = editText.trimmingCharacters(in: .whitespacesAndNewlines)

        // Only call edit handler if the text actually changed
        if !trimmedText.isEmpty, trimmedText != item.name {
            onEditItem?(item.id, trimmedText)
        }

        // Clear editing state
        editingItemId = nil
        editText = ""
        isEditingFocused = false
    }

    private func formatCarbs(_ carbs: Double) -> String {
        if carbs == floor(carbs) {
            return "\(Int(carbs))g"
        } else {
            return String(format: "%.1fg", carbs)
        }
    }
}

#if DEBUG
    struct FoodItemsSelectionView_Previews: PreviewProvider {
        static var previews: some View {
            let sampleItems = [
                AIFoodItem(name: "Sandwich (turkey, cheese)", carbs: 32, emoji: "🥪", absorptionTime: .medium),
                AIFoodItem(name: "Apple", carbs: 15, emoji: "🍎", absorptionTime: .fast),
                AIFoodItem(name: "Diet Soda", carbs: 0, emoji: "🥤", absorptionTime: .fast)
            ]
            let response = AIFoodItemsResponse(foodItems: sampleItems, overallConfidence: 0.85)
            let pendingIds: Set<UUID> = [sampleItems[1].id]

            return VStack {
                StatefulPreviewWrapper(FoodItemSelection(response: response)) { selection in
                    StatefulPreviewWrapper(true) { isExpanded in
                        FoodItemsSelectionView(
                            selection: Binding(
                                get: { selection.wrappedValue },
                                set: { selection.wrappedValue = $0! }
                            ),
                            isExpanded: isExpanded,
                            pendingItemIds: pendingIds,
                            onToggleItem: { itemId in
                                selection.wrappedValue.toggleSelection(for: itemId)
                            },
                            onEditItem: { itemId, newDescription in
                                print("Edit item \(itemId): \(newDescription)")
                            },
                            onOpenChat: {
                                print("Open chat")
                            }
                        )
                        .padding()
                        .background(Color(.secondarySystemGroupedBackground))
                        .cornerRadius(10)
                        .padding()
                    }
                }
            }
        }
    }

    struct StatefulPreviewWrapper<Value, Content: View>: View {
        @State var value: Value
        var content: (Binding<Value>) -> Content

        init(_ value: Value, @ViewBuilder content: @escaping (Binding<Value>) -> Content) {
            _value = State(initialValue: value)
            self.content = content
        }

        var body: some View {
            content($value)
        }
    }
#endif
