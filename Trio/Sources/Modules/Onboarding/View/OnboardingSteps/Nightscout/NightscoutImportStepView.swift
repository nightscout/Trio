import SwiftUI

struct NightscoutImportStepView: View {
    @Bindable var state: Onboarding.StateModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(
                "Please choose if you want to import existing therapy settings from Nightscout or start from scratch."
            ).font(.headline)
                .padding(.horizontal)

            ForEach([NightscoutImportOption.useImport, NightscoutImportOption.skipImport], id: \.self) { option in
                Button(action: {
                    state.nightscoutImportOption = option
                }) {
                    HStack {
                        Image(systemName: state.nightscoutImportOption == option ? "largecircle.fill.circle" : "circle")
                            .foregroundColor(state.nightscoutImportOption == option ? .accentColor : .secondary)
                            .imageScale(.large)

                        Text(option.displayName)
                            .foregroundColor(.primary)

                        Spacer()
                    }
                    .padding()
                    .background(Color.chart.opacity(0.45))
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(
                    "Trio will import the following therapy settings from your Nightscout instance:"
                )
                VStack(alignment: .leading) {
                    Text("• Glucose Targets")
                    Text("• Basal Rates")
                    Text("• Carb Ratios")
                    Text("• Insulin Sensitivities")
                }
            }
            .padding(.horizontal)
            .font(.footnote)
            .foregroundStyle(Color.secondary)
        }
    }
}
