import SwiftUI

/// A user message bubble (right-aligned, colored background)
struct UserMessageBubble: View {
    let text: String

    var body: some View {
        HStack {
            Spacer(minLength: 60)

            Text(text)
                .font(.body)
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.accentColor)
                .cornerRadius(18)
        }
    }
}

/// An assistant message bubble (left-aligned, secondary background)
struct AssistantMessageBubble: View {
    let text: String

    var body: some View {
        HStack {
            Text(text)
                .font(.body)
                .foregroundColor(.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(18)

            Spacer(minLength: 60)
        }
    }
}

/// A system event message (centered, subtle styling)
struct SystemEventMessageView: View {
    let text: String

    var body: some View {
        HStack {
            Spacer()

            HStack(spacing: 6) {
                Image(systemName: "pencil.circle")
                    .font(.caption)
                Text(text)
                    .font(.caption)
            }
            .foregroundColor(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(.tertiarySystemFill))
            .cornerRadius(12)

            Spacer()
        }
    }
}

/// A typing indicator for when the AI is processing
struct TypingIndicator: View {
    @State private var dotOpacities: [Double] = [0.3, 0.3, 0.3]

    var body: some View {
        HStack {
            HStack(spacing: 4) {
                ForEach(0 ..< 3, id: \.self) { index in
                    Circle()
                        .fill(Color.secondary)
                        .frame(width: 8, height: 8)
                        .opacity(dotOpacities[index])
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(18)

            Spacer(minLength: 60)
        }
        .onAppear {
            animateDots()
        }
    }

    private func animateDots() {
        for index in 0 ..< 3 {
            withAnimation(
                .easeInOut(duration: 0.4)
                    .repeatForever(autoreverses: true)
                    .delay(Double(index) * 0.15)
            ) {
                dotOpacities[index] = 1.0
            }
        }
    }
}

/// Header view for the carb summary showing AI sparkle icon
struct AICarbSummaryHeader: View {
    let totalCarbs: Double
    let itemCount: Int
    let isUpdating: Bool

    var body: some View {
        HStack(spacing: 8) {
            // AI indicator
            HStack(spacing: 4) {
                AnimatedSparkleIcon(isAnimating: isUpdating)
                Text("AI Estimate", comment: "Label for AI-generated carb estimate")
                    .font(.caption.bold())
            }
            .foregroundColor(.secondary)

            Spacer()

            // Total carbs
            VStack(alignment: .trailing, spacing: 2) {
                Text(formatCarbs(totalCarbs))
                    .font(.title2.bold().monospacedDigit())
                    .foregroundColor(.primary)
                Text(itemCountLabel)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .totalShimmer(isAnimating: isUpdating)
        }
    }

    private var itemCountLabel: String {
        if itemCount == 1 {
            return String(localized: "1 item", comment: "Single item count")
        } else {
            return String(localized: "\(itemCount) items", comment: "Multiple item count")
        }
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
    struct ChatMessageBubbles_Previews: PreviewProvider {
        static var previews: some View {
            VStack(spacing: 16) {
                UserMessageBubble(text: "Actually the rice is brown rice")

                AssistantMessageBubble(
                    text: "I've updated the rice to brown rice. The carb count is now slightly lower at 35g instead of 40g since brown rice has more fiber."
                )

                SystemEventMessageView(text: "User updated 'Ground Beef' to 'Corned Beef Hash'")

                TypingIndicator()

                AICarbSummaryHeader(totalCarbs: 47, itemCount: 3, isUpdating: false)
                    .padding()
                    .background(Color(.systemGroupedBackground))
                    .cornerRadius(12)

                AICarbSummaryHeader(totalCarbs: 47, itemCount: 3, isUpdating: true)
                    .padding()
                    .background(Color(.systemGroupedBackground))
                    .cornerRadius(12)
            }
            .padding()
        }
    }
#endif
