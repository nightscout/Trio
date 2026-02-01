import SwiftUI

/// Routes message rendering to the appropriate component based on message type
struct ChatMessageView: View {
    let message: AIConversationMessage
    let isUpdating: Bool
    let onAccept: (() -> Void)?

    var body: some View {
        switch message.content {
        case let .text(text):
            textMessageView(text: text, role: message.role)

        case let .carbSummary(items, canAccept):
            ChatCarbSummaryView(
                items: items,
                canAccept: canAccept,
                isUpdating: isUpdating,
                onAccept: onAccept
            )

        case let .systemEvent(event):
            SystemEventMessageView(text: event)
        }
    }

    @ViewBuilder private func textMessageView(text: String, role: AIMessageRole) -> some View {
        switch role {
        case .user:
            UserMessageBubble(text: text)
        case .assistant:
            AssistantMessageBubble(text: text)
        case .system:
            // System text messages are displayed as subtle centered text
            SystemEventMessageView(text: text)
        }
    }
}

/// A list of chat messages with proper spacing and alignment
struct ChatMessageList: View {
    let messages: [AIConversationMessage]
    let isProcessing: Bool
    let onAccept: () -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(messages) { message in
                        ChatMessageView(
                            message: message,
                            isUpdating: isProcessing,
                            onAccept: isCarbSummary(message) ? onAccept : nil
                        )
                        .id(message.id)
                    }

                    // Typing indicator when processing
                    if isProcessing {
                        TypingIndicator()
                            .id("typing-indicator")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .onChange(of: messages.count) { _ in
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: isProcessing) { processing in
                if processing {
                    scrollToTypingIndicator(proxy: proxy)
                }
            }
        }
    }

    private func isCarbSummary(_ message: AIConversationMessage) -> Bool {
        if case .carbSummary = message.content {
            return true
        }
        return false
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        if let lastMessage = messages.last {
            withAnimation(.easeOut(duration: 0.3)) {
                proxy.scrollTo(lastMessage.id, anchor: .bottom)
            }
        }
    }

    private func scrollToTypingIndicator(proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.3)) {
            proxy.scrollTo("typing-indicator", anchor: .bottom)
        }
    }
}

#if DEBUG
    struct ChatMessageView_Previews: PreviewProvider {
        static var previews: some View {
            let sampleItems = [
                AIFoodItem(name: "Sandwich", carbs: 32, emoji: "🥪", absorptionTime: .medium),
                AIFoodItem(name: "Apple", carbs: 15, emoji: "🍎", absorptionTime: .fast)
            ]

            let sampleMessages: [AIConversationMessage] = [
                .assistantMessage(
                    "I've analyzed your food image. I see a turkey sandwich with cheese and an apple. The sandwich appears to be on regular white bread, about 2 slices."
                ),
                .carbSummary(items: sampleItems, canAccept: true),
                .userMessage("Actually the bread is low-carb bread"),
                .systemEvent("User updated 'Sandwich' to 'Sandwich (low-carb bread)'"),
                .assistantMessage(
                    "Thanks for the correction! I've updated the sandwich to use low-carb bread, which significantly reduces the carb count."
                )
            ]

            return NavigationView {
                ChatMessageList(
                    messages: sampleMessages,
                    isProcessing: false,
                    onAccept: { print("Accept") }
                )
                .navigationTitle("Chat Preview")
            }
        }
    }
#endif
