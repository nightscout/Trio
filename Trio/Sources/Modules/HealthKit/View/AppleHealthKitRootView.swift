import SwiftUI
import Swinject

extension AppleHealthKit {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()

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
                    booleanValue: $state.useAppleHealth,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = String(localized: "Connect to Apple Health")
                        }
                    ),
                    units: state.units,
                    type: .boolean,
                    label: String(localized: "Connect to Apple Health"),
                    miniHint: String(localized: "Allow Trio to read from and write to Apple Health."),
                    verboseHint:
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Default: OFF").bold()
                        Text("This allows Trio to read from and write to Apple Health.")
                        Text("Warning: You must also give permissions in iOS System Settings for the Health app.").bold()
                    },
                    headerText: String(localized: "Apple Health Integration")
                )

                if state.useAppleHealth {
                    SettingInputSection(
                        decimalValue: $decimalPlaceholder,
                        booleanValue: $state.importMealsFromAppleHealth,
                        shouldDisplayHint: $shouldDisplayHint,
                        selectedVerboseHint: Binding(
                            get: { selectedVerboseHint },
                            set: {
                                selectedVerboseHint = $0.map { AnyView($0) }
                                hintLabel = String(localized: "Import Meals from Apple Health")
                            }
                        ),
                        units: state.units,
                        type: .boolean,
                        label: String(localized: "Import Meals from Apple Health"),
                        miniHint: String(
                            localized: "Import carbs, fat, and protein logged by other apps into Trio."
                        ),
                        verboseHint:
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Default: OFF").bold()
                            Text(
                                "When enabled, Trio imports carbohydrate, fat, and protein entries " +
                                    "recorded by other apps (such as MyFitnessPal or Cronometer) from Apple Health."
                            )
                            Text(
                                "Samples written by Trio itself are excluded to prevent duplicates."
                            )
                            Text(
                                "Note: Imported fat and protein will trigger Trio's Fat-Protein-Unit (FPU) " +
                                    "calculations if FPU conversion is enabled."
                            ).bold()
                        },
                        headerText: String(localized: "Meal Import")
                    )
                }

                if !state.needShowInformationTextForSetPermissions {
                    Section {
                        VStack {
                            HStack {
                                Image(systemName: "exclamationmark.circle.fill")
                                Text("Give Apple Health Write Permissions")
                            }.padding(.bottom)
                            VStack(alignment: .leading, spacing: 5) {
                                Text("1. Open the Settings app on your iOS device.")
                                Text(
                                    "2. Scroll down or type \"Health\" in the settings search bar and select the \"Health\" app."
                                )
                                Text("3. Tap on \"Data Access & Devices\".")
                                Text("4. Find and select \"Trio\" from the list of apps.")
                                Text("5. Ensure that the \"Write Data\" option is enabled for the desired health metrics.")
                            }.font(.footnote)
                        }
                        .padding(.vertical)
                        .foregroundColor(Color.secondary)
                    }.listRowBackground(Color.chart)
                }
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
            .scrollContentBackground(.hidden).background(appState.trioBackgroundColor(for: colorScheme))
            .onAppear(perform: configureView)
            .navigationTitle("Apple Health")
            .navigationBarTitleDisplayMode(.automatic)
        }
    }
}
