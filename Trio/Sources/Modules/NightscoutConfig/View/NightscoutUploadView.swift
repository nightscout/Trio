import SwiftUI

struct NightscoutUploadView: View {
    @ObservedObject var state: NightscoutConfig.StateModel

    @State private var shouldDisplayHint: Bool = false
    @State var hintDetent = PresentationDetent.large
    @State var selectedVerboseHint: AnyView?
    @State var hintLabel: String?
    @State private var decimalPlaceholder: Decimal = 0.0
    @State private var booleanPlaceholder: Bool = false

    @Environment(\.colorScheme) var colorScheme
    @Environment(AppState.self) var appState

    var body: some View {
        List {
            SettingInputSection(
                decimalValue: $decimalPlaceholder,
                booleanValue: $state.isUploadEnabled,
                shouldDisplayHint: $shouldDisplayHint,
                selectedVerboseHint: Binding(
                    get: { selectedVerboseHint },
                    set: {
                        selectedVerboseHint = $0.map { AnyView($0) }
                        hintLabel = String(localized: "Allow Uploading to Nightscout")
                        shouldDisplayHint = true
                    }
                ),
                units: state.units,
                type: .boolean,
                label: String(localized: "Allow Uploading to Nightscout"),
                miniHint: String(localized: "Enable uploading of selected data sets to Nightscout."),
                verboseHint:
                VStack(alignment: .leading, spacing: 10) {
                    Text("Default: OFF").bold()
                    Text(
                        "The Upload Treatments toggle enables uploading of the following data sets to your connected Nightscout URL:"
                    )
                    VStack(alignment: .leading, spacing: 5) {
                        Text("• Carbs")
                        Text("• Temp Targets")
                        Text("• Device Status")
                        Text("• Preferences")
                        Text("• Settings")
                    }
                }
            )

            SettingInputSection(
                decimalValue: $decimalPlaceholder,
                booleanValue: $state.uploadGlucose,
                shouldDisplayHint: $shouldDisplayHint,
                selectedVerboseHint: Binding(
                    get: { selectedVerboseHint },
                    set: {
                        selectedVerboseHint = $0.map { AnyView($0) }
                        hintLabel = String(localized: "Upload Glucose")
                        shouldDisplayHint = true
                    }
                ),
                units: state.units,
                type: .boolean,
                label: String(localized: "Upload Glucose"),
                miniHint: String(localized: "Enable uploading of CGM readings to Nightscout."),
                verboseHint: VStack(alignment: .leading, spacing: 10) {
                    Text("Default: OFF").bold()
                    Text("Enabling this setting allows CGM readings from Trio to be used in Nightscout.")
                }
            )
        }
        .listSectionSpacing(sectionSpacing)
        .sheet(isPresented: $shouldDisplayHint) {
            SettingInputHintView(
                hintDetent: $hintDetent,
                shouldDisplayHint: $shouldDisplayHint,
                hintLabel: hintLabel ?? "",
                hintText: selectedVerboseHint ?? AnyView(EmptyView()),
                sheetTitle: String(localized: "Help", comment: "Help sheet title")
            )
        }
        .navigationTitle("Upload")
        .navigationBarTitleDisplayMode(.automatic)
        .scrollContentBackground(.hidden)
        .background(appState.trioBackgroundColor(for: colorScheme))
    }
}
