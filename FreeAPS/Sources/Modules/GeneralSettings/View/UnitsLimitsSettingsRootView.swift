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
                    miniHint: """
                    The highest amount of insulin Trio can allow to be active at any given time.
                    Default: 0 units
                    """,
                    verboseHint: VStack {
                        Text("Default: 0 units").bold()
                        Text("""
                             
                             This must be greater than 0 for any automatic temp basals or SMBs to be given.
                             """).bold().italic()
                        Text("""

                        The maximum amount of Insulin On Board (IOB) from all sources - both basal and bolus - that Trio is allowed to accumulate to treat higher-than-target glucose.

                        If a calculated amount exceeds this limit, the suggested and/or delivered amount will be reduced so that active insulin on board (IOB) will not exceed this safety limit.
                        """)
                        Text("Manually entered bolus amounts are not restricted by this limit.").italic()
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
                    miniHint: """
                    Largest bolus of insulin allowed
                    Default: 10 units
                    """,
                    verboseHint: VStack {
                        Text("Default: 10 units").bold()
                        Text("""

                        The maximum bolus allowed to be delivered at one time. This limits manual and automatic bolus.

                        Most set this to their largest meal bolus. Then, adjust if needed.

                        If you attempt to request a bolus larger than this, the bolus will not be accepted.
                        """)
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
                    miniHint: """
                    Largest basal rate allowed
                    Default: 2.0 units
                    """,
                    verboseHint: VStack {
                        Text("Default: 2.0 units").bold()
                        Text("""

                        The maximum basal rate allowed to be set or scheduled.

                        This applies to both automatic or manual basal rates.
                        """)
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
                    miniHint: """
                    The highest amount of carbs Trio can use in dosing calculations.
                    Default: 120 carbs
                    """,
                    verboseHint: VStack {
                        Text("Default: 120 carbs").bold()
                        Text("""

                        Maximum Carbs On Board (COB) allowed. If more carbs are entered than allowed by this limit, Trio will cap the current COB in calculations to maxCOB and remain at max until remaining carbs have shown to be absorbed.

                        """)
                        Text("This is an important limit when UAM is ON.").italic()
                    }
                )
            }
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
