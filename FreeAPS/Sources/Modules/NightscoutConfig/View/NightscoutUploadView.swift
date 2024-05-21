
import SwiftUI

struct NightscoutUploadView: View {
    @ObservedObject var state: NightscoutConfig.StateModel

    var body: some View {
        Form {
            Section {
                Toggle("Upload Treatments and Settings", isOn: $state.isUploadEnabled)

                Toggle("Upload Glucose", isOn: $state.uploadGlucose).disabled(!state.changeUploadGlucose)

            } header: {
                Text("Allow Uploading to Nightscout")
            } footer: {
                Text(
                    "The Upload Treatments toggle enables uploading of carbs, temp targets, device status, preferences and settings.\n\nThe Upload Glucose enables uploading of CGM readings."
                )
            }
        }
        .navigationTitle("Upload")
    }
}
