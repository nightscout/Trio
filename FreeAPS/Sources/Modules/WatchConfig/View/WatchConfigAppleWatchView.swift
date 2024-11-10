import SwiftUI

struct WatchConfigAppleWatchView: View {
    @ObservedObject var state: WatchConfig.StateModel

    @State private var shouldDisplayHint: Bool = false
    @State var hintDetent = PresentationDetent.large
    @State var selectedVerboseHint: AnyView?
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

    private func onDelete(offsets: IndexSet) {
        state.devices.remove(atOffsets: offsets)
        state.deleteGarminDevice()
    }

    var body: some View {
        List {
            Section(
                header: Text("Apple Watch Configuration"),
                content: {
                    VStack {
                        Picker(
                            selection: $state.selectedAwConfig,
                            label: Text("Display on Watch")
                        ) {
                            ForEach(AwConfig.allCases) { selection in
                                Text(selection.displayName).tag(selection)
                            }
                        }.padding(.top)

                        HStack(alignment: .center) {
                            Text(
                                "Select the information to display."
                            )
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .lineLimit(nil)
                            Spacer()
                            Button(
                                action: {
                                    hintLabel = "Display on Watch"
                                    selectedVerboseHint =
                                        AnyView(VStack(alignment: .leading, spacing: 10) {
                                            Text("Choose between the following options:")
                                            VStack(alignment: .leading, spacing: 5) {
                                                Text("• Heart Rate")
                                                Text("• Glucose Target")
                                                Text("• Steps")
                                                Text("• ISF")
                                                Text("• % Override")
                                            }
                                        })
                                    shouldDisplayHint.toggle()
                                },
                                label: {
                                    HStack {
                                        Image(systemName: "questionmark.circle")
                                    }
                                }
                            ).buttonStyle(BorderlessButtonStyle())
                        }.padding(.top)
                    }.padding(.bottom)
                }
            ).listRowBackground(Color.chart)

            SettingInputSection(
                decimalValue: $decimalPlaceholder,
                booleanValue: $state.displayFatAndProteinOnWatch,
                shouldDisplayHint: $shouldDisplayHint,
                selectedVerboseHint: Binding(
                    get: { selectedVerboseHint },
                    set: {
                        selectedVerboseHint = $0.map { AnyView($0) }
                        hintLabel = "Show Protein and Fat"
                    }
                ),
                units: state.units,
                type: .boolean,
                label: "Show Protein and Fat",
                miniHint: "Show protein and fat on the Apple Watch.",
                verboseHint: Text("When enabled, protein and fat will show in the carb entry screen of the Apple Watch")
            )

            SettingInputSection(
                decimalValue: $decimalPlaceholder,
                booleanValue: $state.confirmBolusFaster,
                shouldDisplayHint: $shouldDisplayHint,
                selectedVerboseHint: Binding(
                    get: { selectedVerboseHint },
                    set: {
                        selectedVerboseHint = $0.map { AnyView($0) }
                        hintLabel = "Confirm Bolus Faster"
                    }
                ),
                units: state.units,
                type: .boolean,
                label: "Confirm Bolus Faster",
                miniHint: "Removes validation for boluses sent from the paired apple watch.",
                verboseHint: Text(
                    "Enabling this feature removes the confirmation / validation step to initiate a bolus faster from the watch."
                )
            )
        }
        .listSectionSpacing(sectionSpacing)
        .sheet(isPresented: $shouldDisplayHint) {
            SettingInputHintView(
                hintDetent: $hintDetent,
                shouldDisplayHint: $shouldDisplayHint,
                hintLabel: hintLabel ?? "",
                hintText: selectedVerboseHint ?? AnyView(EmptyView()),
                sheetTitle: "Help"
            )
        }
        .navigationTitle("Apple Watch")
        .navigationBarTitleDisplayMode(.automatic)
        .scrollContentBackground(.hidden).background(color)
    }
}
