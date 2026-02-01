import SwiftUI

/// An embedded carb summary component for the chat view
/// Shows current food items with an expandable tree and "Accept" button
struct ChatCarbSummaryView: View {
    let items: [AIFoodItem]
    let canAccept: Bool
    let isUpdating: Bool
    let onAccept: (() -> Void)?

    @State private var isExpanded = false

    private var totalCarbs: Double {
        items.reduce(0) { $0 + $1.carbs }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with total
            AICarbSummaryHeader(
                totalCarbs: totalCarbs,
                itemCount: items.count,
                isUpdating: isUpdating
            )

            // Expandable item list
            if !items.isEmpty {
                expandableItemList
            }

            // Accept button
            if canAccept, onAccept != nil {
                acceptButton
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(.separator).opacity(0.3), lineWidth: 1)
        )
    }

    private var expandableItemList: some View {
        VStack(spacing: 0) {
            // Expand/collapse button
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            }) {
                HStack {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 14)

                    Text(isExpanded ? "Hide items" : "Show items", comment: "Toggle to show/hide food items")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Item list (when expanded)
            if isExpanded {
                VStack(spacing: 0) {
                    ForEach(items) { item in
                        chatItemRow(item: item)

                        if item.id != items.last?.id {
                            Divider()
                                .padding(.leading, 24)
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func chatItemRow(item: AIFoodItem) -> some View {
        HStack(spacing: 6) {
            if let emoji = item.emoji, !emoji.isEmpty {
                Text(emoji)
                    .font(.callout)
            }

            Text(item.name)
                .font(.callout)
                .foregroundColor(.primary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 8)

            Text(formatCarbs(item.carbs))
                .font(.callout.monospacedDigit())
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 6)
        .padding(.leading, 4)
    }

    private var acceptButton: some View {
        Button(action: {
            onAccept?()
        }) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16))
                Text("Accept These Values", comment: "Button to accept AI carb estimates")
                    .font(.subheadline.bold())
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.accentColor)
            .cornerRadius(10)
        }
        .disabled(isUpdating)
        .opacity(isUpdating ? 0.6 : 1.0)
    }

    private func formatCarbs(_ carbs: Double) -> String {
        if carbs == floor(carbs) {
            return "\(Int(carbs))g"
        } else {
            return String(format: "%.1fg", carbs)
        }
    }
}

/// A compact inline version of the carb summary for sticky header
struct CompactCarbSummaryView: View {
    let items: [AIFoodItem]
    let isUpdating: Bool
    let onExpand: () -> Void
    let onAccept: () -> Void

    private var totalCarbs: Double {
        items.reduce(0) { $0 + $1.carbs }
    }

    var body: some View {
        HStack(spacing: 12) {
            // AI indicator and total
            HStack(spacing: 6) {
                AnimatedSparkleIcon(isAnimating: isUpdating)

                Text(formatCarbs(totalCarbs))
                    .font(.headline.monospacedDigit())
                    .foregroundColor(.primary)

                Text("(\(items.count) items)", comment: "Item count in compact view")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .totalShimmer(isAnimating: isUpdating)

            Spacer()

            // Expand button
            Button(action: onExpand) {
                Image(systemName: "chevron.down.circle")
                    .font(.system(size: 20))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)

            // Quick accept button
            Button(action: onAccept) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.accentColor)
            }
            .buttonStyle(.plain)
            .disabled(isUpdating)
            .opacity(isUpdating ? 0.6 : 1.0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
        .shadow(color: Color.black.opacity(0.1), radius: 4, y: 2)
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
    struct ChatCarbSummaryView_Previews: PreviewProvider {
        static var previews: some View {
            let sampleItems = [
                AIFoodItem(name: "Sandwich (turkey, cheese)", carbs: 32, emoji: "🥪", absorptionTime: .medium),
                AIFoodItem(name: "Apple", carbs: 15, emoji: "🍎", absorptionTime: .fast),
                AIFoodItem(name: "Diet Soda", carbs: 0, emoji: "🥤", absorptionTime: .fast)
            ]

            ScrollView {
                VStack(spacing: 20) {
                    ChatCarbSummaryView(
                        items: sampleItems,
                        canAccept: true,
                        isUpdating: false,
                        onAccept: { print("Accept") }
                    )

                    ChatCarbSummaryView(
                        items: sampleItems,
                        canAccept: true,
                        isUpdating: true,
                        onAccept: { print("Accept") }
                    )

                    CompactCarbSummaryView(
                        items: sampleItems,
                        isUpdating: false,
                        onExpand: { print("Expand") },
                        onAccept: { print("Accept") }
                    )
                }
                .padding()
            }
        }
    }
#endif
