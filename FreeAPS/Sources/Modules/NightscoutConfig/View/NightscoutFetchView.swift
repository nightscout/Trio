
import SwiftUI

struct NightscoutFetchView: View {
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
            }.listRowBackground(Color.chart)

            Section(
                header: Text("Allow Remote control of Trio"),
                footer: VStack(alignment: .leading, spacing: 2) {
                    Text("Fetch Treatments needs to be allowed to be able to toggle on Remote Control.")
                    Text("\nWhen enabled you allow these remote functions through announcements from Nightscout:")
                    Text(" • ") + Text("Suspend/Resume Pump")
                    Text(" • ") + Text("Opening/Closing Loop")
                    Text(" • ") + Text("Set Temp Basal")
                    Text(" • ") + Text("Enact Bolus")
                }
            )
                {
                    Toggle("Remote Control", isOn: $state.allowAnnouncements)
                        .disabled(!state.isDownloadEnabled)
                }.listRowBackground(Color.chart)
        }
        .navigationTitle("Fetch and Remote")
        .scrollContentBackground(.hidden).background(color)
    }
}
