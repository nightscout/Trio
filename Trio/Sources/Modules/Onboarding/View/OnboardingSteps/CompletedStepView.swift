import SwiftUI

/// Completed step view shown at the end of onboarding.
struct CompletedStepView: View {
    var body: some View {
        VStack(alignment: .center, spacing: 20) {
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

            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(OnboardingChapter.allCases.enumerated()), id: \.element.id) { index, chapter in
                    completedItemsView(
                        stepIndex: index + 1,
                        title: chapter.title,
                        description: chapter.completedDescription
                    )

                    if index < OnboardingChapter.allCases.count {
                        Divider()
                    }
                }
            }
            .padding()
            .background(Color.green.opacity(0.1))
            .cornerRadius(12)

            Text("Remember, you can adjust these settings at any time in the app settings if needed.")
                .multilineTextAlignment(.center)
                .foregroundColor(.primary)
                .bold()
        }
        .padding()
        .frame(maxWidth: .infinity)
    }

    /// A reusable view for displaying setting items in the completed step.
    @ViewBuilder private func completedItemsView(
        stepIndex: Int,
        title: String,
        description: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 14) {
                    stepCount(stepIndex)
                    Text(title)
                        .font(.headline)
                        .bold()
                }

                Spacer()

                Image(systemName: "checkmark")
                    .foregroundStyle(Color.green)
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

    @ViewBuilder private func stepCount(_ count: Int) -> some View {
        Text(count.description)
            .font(.subheadline.bold())
            .frame(width: 26, height: 26, alignment: .center)
            .background(Color.green)
            .foregroundStyle(Color.bgDarkerDarkBlue)
            .clipShape(Capsule())
    }
}

#Preview {
    CompletedStepView()
}
