
import SwiftUI

struct NightscoutUploadView: View {
    @ObservedObject var state: NightscoutConfig.StateModel

    @Environment(\.colorScheme) var colorScheme
    var color: LinearGradient {
        colorScheme == .dark ? LinearGradient(
            gradient: Gradient(colors: [
                Color.bgDarkBlue,
                Color.bgDarkerDarkBlue
            ]),
            startPoint: .top,
            endPoint: .bottom
        )
            :
            LinearGradient(
                gradient: Gradient(colors: [Color.gray.opacity(0.1)]),
                startPoint: .top,
                endPoint: .bottom
            )
    }

    var body: some View {
        Form {
            Section(
                header: Text("Allow Uploading to Nightscout"),
                footer: VStack(alignment: .leading, spacing: 2) {
                    Text(
                        "The Upload Treatments toggle enables uploading of carbs, temp targets, device status, preferences and settings."
                    )
                    Text("\nThe Upload Glucose toggle enables uploading of CGM readings.")

                    if !state.changeUploadGlucose {
                        Text("\nTo flip the Upload Glucose toggle, go to ⚙️ > CGM > CGM Configuration")
                    }
                }
            )
                {
                    Toggle("Upload Treatments and Settings", isOn: $state.isUploadEnabled)

                    Toggle("Upload Glucose", isOn: $state.uploadGlucose).disabled(!state.changeUploadGlucose)
                }.listRowBackground(Color.chart)
        }
        .navigationTitle("Upload")
        .scrollContentBackground(.hidden).background(color)
    }
}
