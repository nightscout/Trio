
import SwiftUI

struct NightscoutFetchView: View {
    @ObservedObject var state: NightscoutConfig.StateModel

    var body: some View {
        Form {
            Section {
                Toggle("Fetch Treatments", isOn: $state.isDownloadEnabled)
                    .onChange(of: state.isDownloadEnabled) { newValue in
                        if !newValue {
                            state.allowAnnouncements = false
                        }
                    }
            } header: {
                Text("Allow Fetching from Nightscout")
            } footer: {
                Text(
                    "The Fetch Treatments toggle enables fetching of carbs and temp targets entered in Careportal or by another uploading device than Trio."
                )
            }
            Section {
                Toggle("Remote Control", isOn: $state.allowAnnouncements)
                    .disabled(!state.isDownloadEnabled)
            } header: { Text("Allow Remote control of Trio")
            } footer: {
                Text(
                    "Fetch Treatments needs to be allowed to be able to toggle on Remote Control.\n\nWhen enabled you allow these remote functions through announcements from Nightscout:\n • Suspend/Resume Pump\n • Opening/Closing Loop\n • Set Temp Basal\n • Enact Bolus."
                )
            }
        }
        .navigationTitle("Fetch and Remote")
    }
}
