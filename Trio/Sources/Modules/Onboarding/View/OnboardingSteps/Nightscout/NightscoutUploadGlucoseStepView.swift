import SwiftUI

struct NightscoutUploadGlucoseStepView: View {
    @Bindable var state: Onboarding.StateModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(
                "Please choose if you want to upload CGM readings from Trio to Nightscout."
            )
            .font(.headline)
            .padding(.horizontal)
            .multilineTextAlignment(.leading)

            HStack {
                Toggle(isOn: $state.uploadGlucose) {
                    Text("Upload Glucose")
                }.tint(Color.accentColor)
            }
            .padding()
            .background(Color.chart.opacity(0.65))
            .cornerRadius(10)

            Text("Enabling this setting allows CGM readings from Trio to be used in Nightscout.")
                .padding(.horizontal)
                .font(.footnote)
                .foregroundStyle(Color.secondary)
                .multilineTextAlignment(.leading)
        }
    }
}
