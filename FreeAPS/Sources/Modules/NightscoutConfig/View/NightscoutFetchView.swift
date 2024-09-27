
import SwiftUI

struct NightscoutFetchView: View {
    @ObservedObject var state: NightscoutConfig.StateModel

    @State private var shouldDisplayHint: Bool = false
    @State var hintDetent = PresentationDetent.large
    @State var selectedVerboseHint: String?
    @State var hintLabel: String?
    @State private var decimalPlaceholder: Decimal = 0.0
    @State private var booleanPlaceholder: Bool = false

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
            SettingInputSection(
                decimalValue: $decimalPlaceholder,
                booleanValue: $state.isDownloadEnabled,
                shouldDisplayHint: $shouldDisplayHint,
                selectedVerboseHint: Binding(
                    get: { selectedVerboseHint },
                    set: {
                        selectedVerboseHint = $0
                        hintLabel = "Allow Fetching from Nightscout"
                    }
                ),
                units: state.units,
                type: .boolean,
                label: "Allow Fetching from Nightscout",
                miniHint: "Enable fetching of selected data sets from Nightscout. See hint for more details.",
                verboseHint: "The Fetch Treatments toggle enables fetching of carbs and temp targets entered in Careportal or by another uploading device than Trio from Nightscout.",
                headerText: "Remote & Fetch Capabilities"
            )

            if state.isDownloadEnabled {
                SettingInputSection(
                    decimalValue: $decimalPlaceholder,
                    booleanValue: $state.allowAnnouncements,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0
                            hintLabel = "Allow Remote Control of Trio"
                        }
                    ),
                    units: state.units,
                    type: .boolean,
                    label: "Allow Remote Control of Trio",
                    miniHint: "Enables selected remote control capabilities via Nightscout. See hint for more details.",
                    verboseHint: "When enabled you allow these remote functions through announcements from Nightscout: \n • Suspend/Resume Pump \n • Opening/Closing Loop \n  • Set Temp Basal \n • Enact Bolus"
                )
            } else {
                Section {
                    Text("'Allow Fetching from Nightscout' must be enabled to allow for Trio Remote Control.")
                }.listRowBackground(Color.tabBar)
            }
        }
        .sheet(isPresented: $shouldDisplayHint) {
            SettingInputHintView(
                hintDetent: $hintDetent,
                shouldDisplayHint: $shouldDisplayHint,
                hintLabel: hintLabel ?? "",
                hintText: selectedVerboseHint ?? "",
                sheetTitle: "Help"
            )
        }
        .navigationTitle("Fetch & Remote")
        .navigationBarTitleDisplayMode(.automatic)
        .scrollContentBackground(.hidden).background(color)
    }
}
