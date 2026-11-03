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
            SettingInputSection(
                decimalValue: $decimalPlaceholder,
                booleanValue: $state.confirmBolusFaster,
                shouldDisplayHint: $shouldDisplayHint,
                selectedVerboseHint: Binding(
                    get: { selectedVerboseHint },
                    set: {
                        selectedVerboseHint = $0.map { AnyView($0) }
                        hintLabel = String(localized: "Confirm Bolus Faster")
                    }
                ),
                units: state.units,
                type: .boolean,
                label: String(localized: "Confirm Bolus Faster"),
                miniHint: String(localized: "Reduce the number of crown rotations required for bolus confirmation."),
                verboseHint: Text(
                    "Enabling this feature lowers the number of turns on the crown dial required when confirming a bolus."
                ),
                headerText: String(localized: "Apple Watch Configuration")
            )

            Section {
                VStack {
                    Picker(
                        selection: $state.watchUsageMode,
                        label: Text("Watch Usage Mode")
                    ) {
                        ForEach(WatchUsageMode.allCases) { selection in
                            Text(selection.displayName).tag(selection)
                        }
                    }.padding(.top)

                    HStack(alignment: .center) {
                        Text(
                            "Choose which actions can be started from the Apple Watch. See hint for more details."
                        )
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .lineLimit(nil)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Button(
                            action: {
                                hintLabel = String(localized: "Watch Usage Mode")
                                selectedVerboseHint =
                                    AnyView(
                                        VStack(alignment: .leading, spacing: 10) {
                                            Text(
                                                "Choose which actions can be started from the Apple Watch. Actions the selected mode does not allow are hidden on the watch and rejected by Trio."
                                            )
                                            VStack(alignment: .leading, spacing: 5) {
                                                Text("Companion (Default):").bold()
                                                Text("Bolus, carb and meal entries, overrides and temp targets.")
                                            }
                                            VStack(alignment: .leading, spacing: 5) {
                                                Text("Adjustments:").bold()
                                                Text("Overrides and temp targets only. No bolus, carb or meal entries.")
                                            }
                                            VStack(alignment: .leading, spacing: 5) {
                                                Text("View:").bold()
                                                Text("Read-only. No treatments, overrides or temp targets.")
                                            }
                                        }
                                    )
                                shouldDisplayHint.toggle()
                            },
                            label: {
                                HStack {
                                    Image(systemName: "questionmark.circle").accessibilityLabel(Text("More information"))
                                }
                            }
                        ).buttonStyle(BorderlessButtonStyle())
                    }.padding(.top)
                }.padding(.bottom)
            }.settingsSearchTarget(label: String(localized: "Watch Usage Mode"))

            SettingInputSection(
                decimalValue: $decimalPlaceholder,
                booleanValue: $state.showForecastWatch,
                shouldDisplayHint: $shouldDisplayHint,
                selectedVerboseHint: Binding(
                    get: { selectedVerboseHint },
                    set: {
                        selectedVerboseHint = $0.map { AnyView($0) }
                        hintLabel = String(localized: "Show forecast on Watch")
                    }
                ),
                units: state.units,
                type: .boolean,
                label: String(localized: "Show Forecast on Watch"),
                miniHint: String(localized: "Shows forecast on the Apple Watch"),
                verboseHint: Text(
                    "Enable this feature to show the forecast on the Apple Watch"
                ),
                headerText: String(localized: "Apple Watch Configuration")
            )

            Section(
                header: Text("Contact Image"),
                content: {
                    VStack {
                        HStack {
                            NavigationLink("Contacts Configuration") {
                                ContactImage.RootView(resolver: resolver)
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
                sheetTitle: String(localized: "Help", comment: "Help sheet title")
            )
        }
        .navigationTitle("Apple Watch")
        .navigationBarTitleDisplayMode(.automatic)
        .settingsHighlightScroll()
        .scrollContentBackground(.hidden)
        .background(appState.trioBackgroundColor(for: colorScheme))
    }
}
