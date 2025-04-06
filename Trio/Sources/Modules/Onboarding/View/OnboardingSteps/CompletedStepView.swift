import SwiftUI

/// Completed step view shown at the end of onboarding.
struct CompletedStepView: View {
    var body: some View {
        VStack(alignment: .center, spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.green)

            Text("You're All Set!")
                .font(.title)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)

            Text(
                "You've successfully completed the initial setup of Trio. Tap 'Get Started' to save your settings and get ready to start using Trio."
            )
            .multilineTextAlignment(.center)
            .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                ForEach(
                    OnboardingStep.allCases.filter { $0 != .welcome && $0 != .startupGuide && $0 != .completed },
                    id: \.self
                ) { step in
                    SettingItemView(step: step, icon: step.iconName, title: step.title)
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

/// A reusable view for displaying setting items in the completed step.
struct SettingItemView: View {
    let step: OnboardingStep
    let icon: String
    let title: String

    var body: some View {
        HStack(spacing: 15) {
            if step == .nightscout {
                Image(icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 40, height: 24)
                    .colorMultiply(Color.green)
            } else {
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundColor(.green)
                    .frame(width: 40)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
            }

            Spacer()

            Image(systemName: "checkmark")
                .foregroundColor(.green)
        }
        .padding(.vertical, 8)
    }
}
