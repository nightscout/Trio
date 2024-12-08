import SwiftUI

struct NightscoutUploadView: View {
    @ObservedObject var state: NightscoutConfig.StateModel

    @State private var shouldDisplayHint: Bool = false
    @State var hintDetent = PresentationDetent.large
    @State var selectedVerboseHint: String?
    @State var hintLabel: String?
    @State private var decimalPlaceholder: Decimal = 0.0
    @State private var booleanPlaceholder: Bool = false

    @Environment(\.colorScheme) var colorScheme
    @Environment(AppState.self) var appState

    var body: some View {
        Form {
            SettingInputSection(
                decimalValue: $decimalPlaceholder,
                booleanValue: $state.isUploadEnabled,
                shouldDisplayHint: $shouldDisplayHint,
                selectedVerboseHint: Binding(
                    get: { selectedVerboseHint },
                    set: {
                        selectedVerboseHint = $0
                        hintLabel = "Allow Uploading to Nightscout"
                        shouldDisplayHint = true
                    }
                ),
                units: state.units,
                type: .boolean,
                label: "Allow Uploading to Nightscout",
                miniHint: "Enables upload of selected data sets to Nightscout. See hint for more details.",
                verboseHint: "The Upload Treatments toggle enables uploading of carbs, temp targets, device status, preferences and settings."
            )

            if state.changeUploadGlucose {
                SettingInputSection(
                    decimalValue: $decimalPlaceholder,
                    booleanValue: $state.uploadGlucose,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0
                            hintLabel = "Upload Glucose"
                            shouldDisplayHint = true
                        }
                    ),
                    units: state.units,
                    type: .boolean,
                    label: "Upload Glucose",
                    miniHint: "Enables uploading of CGM readings to Nightscout.",
                    verboseHint: "Write stuff here."
                )
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
        .navigationTitle("Upload")
        .navigationBarTitleDisplayMode(.automatic)
        .scrollContentBackground(.hidden)
        .background(appState.trioBackgroundColor(for: colorScheme))
    }
}
