import SwiftUI

/// Welcome step view shown at the beginning of onboarding.
struct WelcomeStepView: View {
    var body: some View {
        VStack(alignment: .center, spacing: 20) {
            PulsingLogoAnimation()

            Spacer(minLength: 10)

            VStack(alignment: .leading, spacing: 20) {
                Text("Hi there!")
                    .font(.title2)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)

                Text(
                    "Welcome to Trio - an automated insulin delivery system for iOS based on the OpenAPS algorithm with adaptations."
                )
                .multilineTextAlignment(.leading)
                .foregroundColor(.secondary)

                Text(
                    "Trio is designed to help manage your diabetes efficiently. To get the most out of the app, we'll guide you through setting up some essential parameters."
                )
                .multilineTextAlignment(.leading)
                .foregroundColor(.secondary)

                Text("Let's go through a few quick steps to ensure Trio works optimally for you.")
                    .multilineTextAlignment(.leading)
                    .foregroundColor(.primary)
                    .bold()
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .frame(maxWidth: .infinity)
    }
}
