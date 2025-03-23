import SwiftUI

/// Welcome step view shown at the beginning of onboarding.
struct WelcomeStepView: View {
    var body: some View {
        VStack(alignment: .center, spacing: 20) {
            Text("Welcome to Trio!")
                .font(.title2)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)

            Text(
                "Trio is designed to help manage your diabetes efficiently. To get the most out of the app, we'll guide you through setting up some essential parameters."
            )
            .multilineTextAlignment(.center)
            .foregroundColor(.secondary)

            Text("Let's go through a few quick steps to ensure Trio works optimally for you.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            Image("trioCircledNoBackground")
                .resizable()
                .scaledToFit()
                .frame(height: 100)
                .padding()
        }
        .padding()
        .frame(maxWidth: .infinity)
    }
}

/// Completed step view shown at the end of onboarding.
struct CompletedStepView: View {
    var body: some View {
        VStack(alignment: .center, spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.green)
                .padding()

            Text("You're All Set!")
                .font(.title)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)

            Text(
                "You've successfully completed the initial setup of Trio. Your settings have been saved and you're ready to start using the app."
            )
            .multilineTextAlignment(.center)
            .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                SettingItemView(icon: "target", title: "Glucose Target", description: "Your target range is set")
                SettingItemView(
                    icon: "chart.xyaxis.line",
                    title: "Basal Profile",
                    description: "Your basal profile is configured"
                )
                SettingItemView(icon: "fork.knife", title: "Carb Ratio", description: "Your carb ratio is defined")
                SettingItemView(icon: "drop.fill", title: "Insulin Sensitivity", description: "Your ISF is established")
            }
            .padding()
            .background(Color.green.opacity(0.1))
            .cornerRadius(12)

            Text("Remember, you can adjust these settings at any time in the app settings if needed.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top)
        }
        .padding()
        .frame(maxWidth: .infinity)
    }
}

/// A reusable view for displaying setting items in the completed step.
struct SettingItemView: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 15) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(.green)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)

                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Image(systemName: "checkmark")
                .foregroundColor(.green)
        }
        .padding(.vertical, 8)
    }
}
