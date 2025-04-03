import SwiftUI

struct NightscoutImportStepView: View {
    @Bindable var state: Onboarding.StateModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(
                "Before you proceed, please decide if you want to import existing therapy settings from Nightscout (your \"default profile\"), or if you would like to start from scratch."
            )

            Text("Tap \"Import Settings\" to begin, or \"Next\" to skip.")
                .foregroundStyle(Color.secondary)

            Button(action: {
                let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
                impactHeavy.impactOccurred()

                // TODO: handle import
            }) {
                HStack {
                    Text("Import Settings").bold()
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 8)
            }
            .disabled(state.url.isEmpty || state.secret.isEmpty)
            .buttonStyle(.borderedProminent)

            VStack(alignment: .leading, spacing: 10) {
                Text(
                    "Trio will import the following therapy settings from Nightscout:"
                )
                VStack(alignment: .leading) {
                    Text("• Basal Rates")
                    Text("• Insulin Sensitivities")
                    Text("• Carb Ratios")
                    Text("• Glucose Targets")
                }
            }
            .font(.footnote)
            .foregroundStyle(Color.secondary)
        }
    }
}
