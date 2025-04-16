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
                ForEach(
                    nonInfoOnboardingSteps,
                    id: \.self
                ) { step in
                    SettingItemView(step: step, icon: step.iconName, title: step.title, type: .complete)
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
}
