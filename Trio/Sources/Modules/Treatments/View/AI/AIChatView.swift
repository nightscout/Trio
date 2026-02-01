import SwiftUI

/// Full-screen chat modal for refining food analysis with AI
struct AIChatView: View {
    @ObservedObject var conversationManager: AIConversationManager
    @Binding var isPresented: Bool
    let onAcceptValues: (FoodItemSelection) -> Void

    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Sticky header with current totals
                stickyHeader

                Divider()

                // Chat message list
                ChatMessageList(
                    messages: conversationManager.messages,
                    isProcessing: conversationManager.isProcessing,
                    onAccept: acceptAndClose
                )

                Divider()

                // Input area
                chatInputArea
            }
            .navigationTitle(Text("Refine Food Analysis", comment: "Title for AI chat view"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { isPresented = false }) {
                        Text("Cancel", comment: "Cancel button")
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: acceptAndClose) {
                        Text("Confirm", comment: "Confirm button")
                            .bold()
                    }
                    .disabled(conversationManager.isProcessing)
                }
            }
            .alert(
                Text("Error", comment: "Error alert title"),
                isPresented: Binding(
                    get: { conversationManager.errorMessage != nil },
                    set: { if !$0 { conversationManager.clearError() } }
                ),
                actions: {
                    Button("OK") {
                        conversationManager.clearError()
                    }
                },
                message: {
                    Text(conversationManager.errorMessage ?? "")
                }
            )
        }
    }

    // MARK: - Sticky Header

    private var stickyHeader: some View {
        CompactCarbSummaryView(
            items: conversationManager.currentItems,
            isUpdating: conversationManager.isProcessing,
            onExpand: { /* Could show expanded view */ },
            onAccept: acceptAndClose
        )
    }

    // MARK: - Chat Input

    private var chatInputArea: some View {
        HStack(spacing: 12) {
            // Text input - using TextEditor for multiline support on iOS 15
            ZStack(alignment: .topLeading) {
                if inputText.isEmpty {
                    Text("Type a message...", comment: "Placeholder for chat input")
                        .foregroundColor(Color(.placeholderText))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 10)
                }
                TextEditor(text: $inputText)
                    .frame(minHeight: 36, maxHeight: 100)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .focused($isInputFocused)
            }
            .background(Color(.systemGray6))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(.systemGray4), lineWidth: 1)
            )

            // Send button
            Button(action: sendMessage) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(canSend ? .accentColor : .secondary)
            }
            .disabled(!canSend)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
    }

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !conversationManager.isProcessing
    }

    // MARK: - Actions

    private func sendMessage() {
        let trimmedText = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }

        inputText = ""
        isInputFocused = false

        Task {
            await conversationManager.sendMessage(trimmedText)
        }
    }

    private func acceptAndClose() {
        let selection = conversationManager.acceptCurrentValues()
        onAcceptValues(selection)
        isPresented = false
    }
}

#if DEBUG
    struct AIChatView_Previews: PreviewProvider {
        static var previews: some View {
            let sampleItems = [
                AIFoodItem(name: "Sandwich", carbs: 32, emoji: "🥪", absorptionTime: .medium),
                AIFoodItem(name: "Apple", carbs: 15, emoji: "🍎", absorptionTime: .fast)
            ]
            let response = AIFoodItemsResponseWithReasoning(
                foodItems: sampleItems,
                overallConfidence: 0.85,
                reasoning: "I see a turkey sandwich on white bread and a medium-sized red apple. The sandwich appears to have about 2 slices of bread."
            )

            let manager = AIConversationManager()

            return AIChatView(
                conversationManager: manager,
                isPresented: .constant(true),
                onAcceptValues: { _ in print("Accepted") }
            )
            .onAppear {
                // Initialize manager with sample data for preview
                Task { @MainActor in
                    manager.initialize(
                        with: response,
                        imageData: Data(),
                        userDescription: nil
                    )
                }
            }
        }
    }
#endif
