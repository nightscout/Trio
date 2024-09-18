import SwiftUI
import Swinject

extension UnitsLimitsSettings {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()
        @State private var shouldDisplayHint: Bool = false
        @State var hintDetent = PresentationDetent.large
        @State var selectedVerboseHint: String?
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
                    decimalValue: $state.maxBolus,
                    booleanValue: $booleanPlaceholder,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0
                            hintLabel = "Max Bolus"
                        }
                    ),
                    units: state.units,
                    type: .decimal("maxBolus"),
                    label: "Max Bolus",
                    miniHint: "Lorem ipsum dolor sit amet, consetetur sadipscing elitr.",
                    verboseHint: "Max Bolus… bla bla bla"
                )

                SettingInputSection(
                    decimalValue: $state.maxBasal,
                    booleanValue: $booleanPlaceholder,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0
                            hintLabel = "Max Basal"
                        }
                    ),
                    units: state.units,
                    type: .decimal("maxBasal"),
                    label: "Max Basal",
                    miniHint: "Lorem ipsum dolor sit amet, consetetur sadipscing elitr.",
                    verboseHint: "Max Basal… bla bla bla"
                )

                SettingInputSection(
                    decimalValue: $state.maxIOB,
                    booleanValue: $booleanPlaceholder,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0
                            hintLabel = NSLocalizedString("Max IOB", comment: "Max IOB")
                        }
                    ),
                    units: state.units,
                    type: .decimal("maxIOB"),
                    label: NSLocalizedString("Max IOB", comment: "Max IOB"),
                    miniHint: "Lorem ipsum dolor sit amet, consetetur sadipscing elitr.",
                    verboseHint: NSLocalizedString(
                        "Max IOB is the maximum amount of insulin on board from all sources – both basal (or SMB correction) and bolus insulin – that your loop is allowed to accumulate to treat higher-than-target BG. Unlike the other two OpenAPS safety settings (max_daily_safety_multiplier and current_basal_safety_multiplier), max_iob is set as a fixed number of units of insulin. As of now manual boluses are NOT limited by this setting. \n\n To test your basal rates during nighttime, you can modify the Max IOB setting to zero while in Closed Loop. This will enable low glucose suspend mode while testing your basal rates settings.",
                        comment: "Max IOB"
                    )
                )

                SettingInputSection(
                    decimalValue: $state.maxCOB,
                    booleanValue: $booleanPlaceholder,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0
                            hintLabel = NSLocalizedString("Max COB", comment: "Max COB")
                        }
                    ),
                    units: state.units,
                    type: .decimal("maxCOB"),
                    label: NSLocalizedString("Max COB", comment: "Max COB"),
                    miniHint: "Lorem ipsum dolor sit amet, consetetur sadipscing elitr.",
                    verboseHint: NSLocalizedString(
                        "The default of maxCOB is 120. (If someone enters more carbs in one or multiple entries, Trio will cap COB to maxCOB and keep it at maxCOB until the carbs entered above maxCOB have shown to be absorbed. Essentially, this just limits UAM as a safety cap against weird COB calculations due to fluky data.)",
                        comment: "Max COB"
                    )
                )
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
