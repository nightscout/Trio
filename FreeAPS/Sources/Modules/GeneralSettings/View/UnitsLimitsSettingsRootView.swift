import SwiftUI
import Swinject

extension UnitsLimitsSettings {
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
        @EnvironmentObject var appIcons: Icons

        private var color: LinearGradient {
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
            List {
                Section(
                    header: Text("Trio Core Setup"),
                    content: {
                        Picker("Glucose Units", selection: $state.unitsIndex) {
                            Text("mg/dL").tag(0)
                            Text("mmol/L").tag(1)
                        }
                    }
                ).listRowBackground(Color.chart)

                SettingInputSection(
                    decimalValue: $state.maxIOB,
                    booleanValue: $booleanPlaceholder,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = NSLocalizedString("Max IOB", comment: "Max IOB")
                        }
                    ),
                    units: state.units,
                    type: .decimal("maxIOB"),
                    label: NSLocalizedString("Max IOB", comment: "Max IOB"),
                    miniHint: "Maximum units of insulin allowed active at any given time.",
                    verboseHint:
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Default: 0 units").bold()
                        Text(
                            "Warning: This must be greater than 0 for any automatic temporary basal rates or SMBs to be given."
                        ).bold()
                        Text(
                            "The maximum amount of Insulin On Board (IOB) above profile basal rates from all sources - positive temporary basal rates, manual or meal boluses, and SMBs - that Trio is allowed to accumulate to address a higher-than-target glucose."
                        )
                        Text(
                            "If a calculated amount exceeds this limit, the suggested and/or delivered amount will be reduced so that active insulin on board (IOB) will not exceed this safety limit."
                        )
                        Text(
                            "Note: You can still manually bolus above this limit, but the suggested bolus amount will never exceed this in the bolus calculator."
                        )
                    }
                )

                SettingInputSection(
                    decimalValue: $state.maxBolus,
                    booleanValue: $booleanPlaceholder,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = "Max Bolus"
                        }
                    ),
                    units: state.units,
                    type: .decimal("maxBolus"),
                    label: "Max Bolus",
                    miniHint: "Largest bolus of insulin allowed.",
                    verboseHint:
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Default: 10 units").bold()
                        Text("The maximum bolus allowed to be delivered at one time. This limits manual and automatic bolus.")
                        Text("Most set this to their largest meal bolus. Then, adjust if needed.")
                        Text("If you attempt to request a bolus larger than this, the bolus will not be accepted.")
                    }
                )

                SettingInputSection(
                    decimalValue: $state.maxBasal,
                    booleanValue: $booleanPlaceholder,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = "Max Basal"
                        }
                    ),
                    units: state.units,
                    type: .decimal("maxBasal"),
                    label: "Max Basal",
                    miniHint: "Largest basal rate allowed.",
                    verboseHint:
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Default: 2.0 units").bold()
                        Text("The maximum basal rate allowed to be set or scheduled.")
                        Text("This applies to both automatic or manual basal rates.")
                    }
                )

                SettingInputSection(
                    decimalValue: $state.maxCOB,
                    booleanValue: $booleanPlaceholder,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = NSLocalizedString("Max COB", comment: "Max COB")
                        }
                    ),
                    units: state.units,
                    type: .decimal("maxCOB"),
                    label: NSLocalizedString("Max COB", comment: "Max COB"),
                    miniHint: "Max carbs Trio can use in dosing calculations.",
                    verboseHint:
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Default: 120 carbs").bold()
                        Text(
                            "Maximum Carbs On Board (COB) allowed. If more carbs are entered than allowed by this limit, Trio will cap the current COB in calculations to Max COB and remain at max until all remaining carbs have shown to be absorbed."
                        )
                        Text("This is an important limit when UAM is ON.")
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
                    sheetTitle: "Help"
                )
            }
            .scrollContentBackground(.hidden).background(color)
            .onAppear(perform: configureView)
            .navigationTitle("General")
            .navigationBarTitleDisplayMode(.automatic)
            .onDisappear {
                state.saveIfChanged()
            }
        }
    }
}
