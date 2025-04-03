import SwiftUI

struct UnitSelectionStepView: View {
    @Bindable var state: Onboarding.StateModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Please choose from the options below.")
                .font(.headline)

            Spacer(minLength: 20)

            HStack {
                Text("Glucose Units")
                Spacer()
                Picker("Glucose Units", selection: $state.units) {
                    ForEach(GlucoseUnits.allCases, id: \.self) { unit in
                        Text(unit.rawValue).tag(unit)
                    }
                }
            }
            .padding()
            .background(Color.chart.opacity(0.65))
            .cornerRadius(10)

            HStack {
                Text("Pump Model")
                Spacer()
                Picker("Pump Model", selection: $state.pumpModel) {
                    ForEach(PumpOptionsForOnboardingUnits.allCases, id: \.self) { pumpModel in
                        Text(pumpModel.displayName).tag(pumpModel)
                    }
                }
            }
            .padding()
            .background(Color.chart.opacity(0.65))
            .cornerRadius(10)

            Text(
                "Note: Choosing your pump model determines which increments for setting up your basal rates are available. You will pair your actual pump after finishing the onboarding process."
            )
            .padding(.vertical)
            .font(.footnote)
            .foregroundStyle(Color.secondary)
        }
    }
}
