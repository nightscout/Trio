import SwiftUI

/// Completed step view shown at the end of onboarding.
struct CompletedStepView: View {
    let isOnboardingCompleted: Bool
    let currentChapter: OnboardingChapter?

    var body: some View {
        VStack(alignment: .center, spacing: 20) {
            if isOnboardingCompleted {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.green)

                Text("You're All Set!")
                    .font(.title)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)

                Text(
                    "You've successfully completed the initial setup of Trio. Tap 'Get Started' to save your settings and start using Trio."
                )
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(OnboardingChapter.allCases.enumerated()), id: \.element.id) { index, chapter in
                    completedItemsView(
                        stepIndex: index + 1,
                        title: chapter.title,
                        description: isChapterCompleted(chapter) ? chapter.completedDescription : chapter.overviewDescription,
                        isCompleted: isChapterCompleted(chapter)
                    )

                    if index < (OnboardingChapter.allCases.count - 1) {
                        Divider()
                    }
                }
            }
            .padding()
            .background(Color.green.opacity(0.1))
            .cornerRadius(12)

            if isOnboardingCompleted {
                Text("Remember, you can adjust these settings at any time in the app settings if needed.")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.primary)
                    .bold()
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
    }

    /// Determines if a chapter should be marked as completed
    private func isChapterCompleted(_ chapter: OnboardingChapter) -> Bool {
        guard let currentChapter else { return isOnboardingCompleted }
        if isOnboardingCompleted { return true }
        return chapter.id <= currentChapter.id
    }

    /// A reusable view for displaying setting items in the completed step.
    @ViewBuilder private func completedItemsView(
        stepIndex: Int,
        title: String,
        description: String,
        isCompleted: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 14) {
                    stepCount(stepIndex, isCompleted: isCompleted)
                    Text(title)
                        .font(.headline)
                        .bold()
                }

                Spacer()

                Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isCompleted ? Color.green : Color.secondary)
                    .font(.headline)
                    .bold()
            }

            Text(description)
                .font(.footnote)
                .foregroundStyle(Color.white.opacity(0.8))
                .padding(.vertical, 8)
                .multilineTextAlignment(.leading)
        }
    }

    @ViewBuilder private func stepCount(_ count: Int, isCompleted: Bool) -> some View {
        Text(count.description)
            .font(.subheadline.bold())
            .frame(width: 26, height: 26, alignment: .center)
            .background(isCompleted ? Color.green : Color.secondary)
            .foregroundStyle(Color.bgDarkerDarkBlue)
            .clipShape(Capsule())
    }
}

#Preview {
    CompletedStepView(
        isOnboardingCompleted: true,
        currentChapter: nil
    )
}
