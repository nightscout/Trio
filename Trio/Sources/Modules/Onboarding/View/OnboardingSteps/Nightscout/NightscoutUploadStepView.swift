import SwiftUI

struct NightscoutUploadStepView: View {
    @Bindable var state: Onboarding.StateModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(
                "Please choose if you want to upload treatment data to Nightscout."
            )
            .font(.headline)
            .padding(.horizontal)
            .multilineTextAlignment(.leading)

            HStack {
                Toggle(isOn: $state.isUploadEnabled) {
                    Text("Allow Uploading to Nightscout")
                }.tint(Color.accentColor)
            }
            .padding()
            .background(Color.chart.opacity(0.65))
            .cornerRadius(10)

            Text(
                "The Upload Treatments toggle enables uploading of the following data sets to your connected Nightscout URL:"
            )
            .padding(.horizontal)
            .font(.footnote)
            .foregroundStyle(Color.secondary)
            .multilineTextAlignment(.leading)

            VStack(alignment: .leading, spacing: 5) {
                Text("• Carbs")
                Text("• Temp Targets")
                Text("• Device Status")
                Text("• Preferences")
                Text("• Settings")
            }
            .padding(.horizontal)
            .font(.footnote)
            .foregroundStyle(Color.secondary)
            .multilineTextAlignment(.leading)

            HStack {
                Toggle(isOn: $state.uploadCGMSensorStates) {
                    Text("Upload CGM Sensor States")
                }.tint(Color.accentColor)
            }
            .padding()
            .background(Color.chart.opacity(0.65))
            .cornerRadius(10)
            .disabled(!state.isUploadEnabled)

            Text(
                "When the sensor delivers no glucose, Trio uploads a note with the sensor state reported by the CGM, such as a sensor failure or warmup. Supported for Dexcom G6 and G7."
            )
            .padding(.horizontal)
            .font(.footnote)
            .foregroundStyle(Color.secondary)
            .multilineTextAlignment(.leading)
        }
    }
}
