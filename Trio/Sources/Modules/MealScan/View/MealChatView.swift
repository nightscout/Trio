import SwiftUI

extension MealScan {
    struct MealChatView: View {
        @Bindable var state: StateModel

        var body: some View {
            VStack(spacing: 0) {
                // Sticky totals bar
                totalsBar

                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            // Meal photo thumbnail
                            if let image = state.capturedImage {
                                Image(uiImage: image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(maxHeight: 200)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .padding(.horizontal)
                            }

                            // Detected foods section
                            detectedFoodsSection

                            Divider()
                                .padding(.horizontal)

                            // Chat messages
                            ForEach(state.chatMessages) { message in
                                chatBubble(for: message)
                                    .id(message.id)
                            }

                            if state.isStreaming {
                                HStack {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                    Text("Thinking...")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .onChange(of: state.chatMessages.count) {
                        if let lastMessage = state.chatMessages.last {
                            withAnimation {
                                proxy.scrollTo(lastMessage.id, anchor: .bottom)
                            }
                        }
                    }
                }

                Divider()

                // Input bar
                inputBar

                // Super bolus recommendation
                superBolusIndicator

                // Confirm button
                confirmButton
            }
        }

        // MARK: - Totals Bar

        private var totalsBar: some View {
            HStack(spacing: 16) {
                totalItem(label: "Carbs", value: state.runningTotals.carbs, unit: "g", color: .blue)
                totalItem(label: "Fat", value: state.runningTotals.fat, unit: "g", color: .orange)
                totalItem(label: "Protein", value: state.runningTotals.protein, unit: "g", color: .red)
                totalItem(label: "Cal", value: state.runningTotals.calories, unit: "", color: .secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(Color(.systemGroupedBackground))
        }

        private func totalItem(label: String, value: Decimal, unit: String, color: Color) -> some View {
            VStack(spacing: 2) {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("\(NSDecimalNumber(decimal: value).intValue)\(unit)")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(color)
            }
            .frame(maxWidth: .infinity)
        }

        // MARK: - Detected Foods

        private var detectedFoodsSection: some View {
            VStack(alignment: .leading, spacing: 6) {
                Text("Detected Foods")
                    .font(.headline)
                    .padding(.horizontal)

                ForEach(Array(state.detectedFoods.enumerated()), id: \.element.id) { index, food in
                    foodRow(food: food, index: index)
                }

                if state.detectedFoods.filter({ !$0.isRemoved }).isEmpty {
                    Text("No foods detected")
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                }
            }
        }

        private func foodRow(food: DetectedFood, index: Int) -> some View {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(food.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .strikethrough(food.isRemoved)
                    if !food.servingDescription.isEmpty {
                        Text(food.servingDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 8) {
                        Text("C: \(NSDecimalNumber(decimal: food.carbs).intValue)g")
                            .foregroundStyle(.blue)
                        Text("F: \(NSDecimalNumber(decimal: food.fat).intValue)g")
                            .foregroundStyle(.orange)
                        Text("P: \(NSDecimalNumber(decimal: food.protein).intValue)g")
                            .foregroundStyle(.red)
                    }
                    .font(.caption)
                }

                Spacer()

                Button {
                    if food.isRemoved {
                        state.restoreFood(at: index)
                    } else {
                        state.removeFood(at: index)
                    }
                } label: {
                    Image(systemName: food.isRemoved ? "arrow.uturn.backward.circle" : "xmark.circle.fill")
                        .foregroundStyle(food.isRemoved ? .blue : .secondary)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 4)
            .opacity(food.isRemoved ? 0.5 : 1)
        }

        // MARK: - Chat Bubbles

        private func chatBubble(for message: ChatMessage) -> some View {
            HStack {
                if message.role == .user { Spacer(minLength: 60) }

                VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                    Text(message.text)
                        .font(.subheadline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            message.role == .user
                                ? Color.blue.opacity(0.15)
                                : Color(.systemGray5)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 16))

                    if let totals = message.updatedTotals {
                        HStack(spacing: 8) {
                            Text("Updated:")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text("C: \(NSDecimalNumber(decimal: totals.carbs).intValue)g")
                                .foregroundStyle(.blue)
                            Text("F: \(NSDecimalNumber(decimal: totals.fat).intValue)g")
                                .foregroundStyle(.orange)
                            Text("P: \(NSDecimalNumber(decimal: totals.protein).intValue)g")
                                .foregroundStyle(.red)
                        }
                        .font(.caption)
                    }
                }

                if message.role == .assistant { Spacer(minLength: 60) }
            }
            .padding(.horizontal)
        }

        // MARK: - Input Bar

        private var inputBar: some View {
            HStack(spacing: 8) {
                TextField("Describe corrections...", text: $state.userInput, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1 ... 4)
                    .padding(8)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 20))

                Button {
                    Task { await state.sendMessage() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.blue)
                }
                .disabled(state.userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || state.isStreaming)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }

        // MARK: - Super Bolus Indicator

        @ViewBuilder
        private var superBolusIndicator: some View {
            switch state.runningTotals.superBolusRecommendation {
            case .yes:
                HStack(spacing: 10) {
                    Image(systemName: "bolt.fill")
                        .font(.title3)
                        .foregroundStyle(.white)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Super Bolus Recommended")
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                        if !state.runningTotals.superBolusReason.isEmpty {
                            Text(state.runningTotals.superBolusReason)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.9))
                        }
                    }
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.white)
                }
                .padding(12)
                .background(Color.orange)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal)
                .padding(.top, 4)

            case .consider:
                HStack(spacing: 10) {
                    Image(systemName: "bolt.circle")
                        .font(.title3)
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Consider Super Bolus")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.primary)
                        if !state.runningTotals.superBolusReason.isEmpty {
                            Text(state.runningTotals.superBolusReason)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
                .padding(12)
                .background(Color.orange.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal)
                .padding(.top, 4)

            case .no:
                EmptyView()
            }
        }

        // MARK: - Confirm Button

        private var confirmButton: some View {
            Button {
                state.confirm()
            } label: {
                Text("Use These Numbers")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.green)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(state.isStreaming)
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
    }
}
