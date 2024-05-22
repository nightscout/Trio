
import SwiftUI

struct NightscoutUploadView: View {
    @ObservedObject var state: NightscoutConfig.StateModel

    var body: some View {
        Form {
            Section(
                header: Text("Allow Uploading to Nightscout"),
                footer: VStack(alignment: .leading, spacing: 2) {
                    Text(
                        "The Upload Treatments toggle enables uploading of carbs, temp targets, device status, preferences and settings."
                    )
                    Text("\nThe Upload Glucose toggle enables uploading of CGM readings.")
                }
            )
                {
                    Toggle("Upload Treatments and Settings", isOn: $state.isUploadEnabled)

                    Toggle("Upload Glucose", isOn: $state.uploadGlucose).disabled(!state.changeUploadGlucose)
                }
        }
        .navigationTitle("Upload")
    }
}
