import SwiftUI
import Swinject

struct WatchConfigAppleWatchView: BaseView {
    let resolver: Resolver
    @ObservedObject var state: WatchConfig.StateModel

    @State private var shouldDisplayHint: Bool = false
    @State var hintDetent = PresentationDetent.large
    @State var selectedVerboseHint: AnyView?
    @State var hintLabel: String?
    @State private var decimalPlaceholder: Decimal = 0.0
    @State private var booleanPlaceholder: Bool = false

    @Environment(\.colorScheme) var colorScheme
    @Environment(AppState.self) var appState

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
                                        AnyView(VStack(alignment: .leading, spacing: 5) {
                                            Text("Choose between the following:")
                                            Text("• Heart Rate")
                                            Text("• Glucose Target")
                                            Text("• Steps")
                                            Text("• ISF")
                                            Text("• % Override")
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
                miniHint: "Allow protein and fat entries on watch.",
                verboseHint: Text("When enabled, protein and fat will show in the carb entry screen of the Apple Watch.")
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
                miniHint: "Reduce the number of crown rotations required for bolus confirmation.",
                verboseHint: Text(
                    "Enabling this feature lowers the number of turns on the crown dial required when confirming a bolus."
                )
            )

            Section(
                header: Text("Contact Trick"),
                content: {
                    VStack {
                        HStack {
                            NavigationLink("Contacts Configuration") {
                                ContactTrick.RootView(resolver: resolver)
                            }.foregroundStyle(Color.accentColor)
                        }
                    }
                }
            ).listRowBackground(Color.chart)
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
        .scrollContentBackground(.hidden)
        .background(appState.trioBackgroundColor(for: colorScheme))
    }
}
