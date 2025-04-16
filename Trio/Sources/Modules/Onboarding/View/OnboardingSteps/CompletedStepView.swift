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
                completedItemsView(
                    stepIndex: 1,
                    title: String(localized: "Prepare Trio"),
                    steps: [.diagnostics, .nightscout, .unitSelection],
                    description: "App diagnostics sharing, Nightscout setup, and unit and pump model selection are all complete."
                )

                Divider()

                completedItemsView(
                    stepIndex: 2,
                    title: String(localized: "Therapy Settings"),
                    steps: [.glucoseTarget, .basalRates, .carbRatio, .insulinSensitivity],
                    description: "Glucose target, basal rates, carb ratios, and insulin sensitivity match your needs."
                )

                Divider()

                completedItemsView(
                    stepIndex: 3,
                    title: String(localized: "Delivery Limits"),
                    steps: [.deliveryLimits],
                    description: "Safety boundaries for insulin delivery and carb entries are set to help Trio keep you safe."
                )

                Divider()

                completedItemsView(
                    stepIndex: 4,
                    title: String(localized: "Algorithm Settings"),
                    steps: [.autosensSettings, .smbSettings, .targetBehavior],
                    description: "Trio’s algorithm features are customized to fit your preferences and needs."
                )
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
        steps _: [OnboardingStep],
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
