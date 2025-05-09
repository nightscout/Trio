import SwiftUI
import Swinject

extension DynamicSettings {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()
        @State private var shouldDisplayHint: Bool = false
        @State var hintDetent = PresentationDetent.large
        @State var selectedVerboseHint: AnyView?
        @State var hintLabel: String?
        @State private var decimalPlaceholder: Decimal = 0.0
        @State private var booleanPlaceholder: Bool = false

        private var conversionFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 1

            return formatter
        }

        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState

        private var formatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            return formatter
        }

        private var glucoseFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            if state.units == .mmolL {
                formatter.maximumFractionDigits = 1
            } else { formatter.maximumFractionDigits = 0 }
            formatter.roundingMode = .halfUp
            return formatter
        }

        var body: some View {
            List {
                Section(
                    header: Text("Dynamic Insulin Sensitivity"),
                    content: {
                        VStack(alignment: .leading) {
                            Picker(
                                selection: $state.dynamicSensitivityType,
                                label: Text("Dynamic ISF").multilineTextAlignment(.leading)
                            ) {
                                ForEach(DynamicSensitivityType.allCases) { selection in
                                    Text(selection.displayName).tag(selection)
                                }
                            }
                            .disabled(!state.hasValidTDD)
                            .padding(.top)

                            HStack(alignment: .center) {
                                let miniHintText = state.hasValidTDD ?
                                    String(
                                        localized: "Dynamically adjust insulin sensitivity using Dynamic Ratio rather than Autosens Ratio."
                                    ) :
                                    String(
                                        localized: "Trio has only been actively used and looping for less than seven days. Cannot enable dynamic ISF."
                                    )
                                let miniHintTextColorForDisabled: Color = colorScheme == .dark ? .orange :
                                    .accentColor
                                let miniHintTextColor: Color = state.hasValidTDD ? .secondary : miniHintTextColorForDisabled

                                Text(miniHintText)
                                    .font(.footnote)
                                    .foregroundColor(miniHintTextColor)
                                    .lineLimit(nil)

                                Spacer()
                                Button(
                                    action: {
                                        hintLabel = String(localized: "Time in Range Chart Style")
                                        selectedVerboseHint =
                                            AnyView(
                                                VStack(alignment: .leading, spacing: 10) {
                                                    Text("Default: Disabled").bold()
                                                    Text(
                                                        "Enabling this feature allows Trio to calculate a new Insulin Sensitivity Factor with each loop cycle dynamically. Trio offers two dynamic formulas:"
                                                    )
                                                    VStack(alignment: .leading, spacing: 10) {
                                                        Text("Logarithmic Dynamic ISF").bold()
                                                        Text(
                                                            "Enabling this feature allows Trio to calculate a new Insulin Sensitivity Factor with each loop cycle by considering your current glucose, the weighted total daily dose of insulin, the set adjustment factor, and a few other data points. This helps tailor your insulin response more accurately in real time."
                                                        )
                                                        Text(
                                                            "Dynamic ISF produces a Dynamic Ratio, replacing the Autosens Ratio, determining how much your profile ISF will be adjusted every loop cycle, ensuring it stays within safe limits set by your Autosens Min/Max settings. It provides more precise insulin dosing by responding to changes in insulin needs throughout the day."
                                                        )
                                                        Text(
                                                            "You can influence the adjustments made by Dynamic ISF primarily by adjusting Autosens Max, Autosens Min, and Adjustment Factor. Other settings also influence Dynamic ISF's response, such as Glucose Target, Profile ISF, Peak Insulin Time, and Weighted Average of TDD."
                                                        )
                                                        Text(
                                                            "Warning: Before adjusting these settings, make sure you are fully aware of the impact those changes will have."
                                                        )
                                                        .bold()
                                                    }

                                                    VStack(alignment: .leading, spacing: 10) {
                                                        Text("Sigmoid Dynamic ISF").bold()
                                                        Text(
                                                            "Turning on the Sigmoid Formula setting alters how your Dynamic Ratio, and thus your New ISF, are calculated using a sigmoid curve."
                                                        )
                                                        Text(
                                                            "The curve's steepness is influenced by the Adjustment Factor, while the Autosens Min/Max settings determine the limits of the ratio adjustment, which can also influence the steepness of the sigmoid curve."
                                                        )
                                                        Text(
                                                            "When using the Sigmoid Formula, the weighted Total Daily Dose has a much lower impact on the dynamic adjustments to sensitivity."
                                                        )
                                                        Text(
                                                            "Careful tuning is essential to avoid overly aggressive insulin changes."
                                                        )
                                                        Text(
                                                            "It is not recommended to set Autosens Max above 150% to maintain safe insulin dosing."
                                                        )
                                                        Text(
                                                            "There has been no empirical data analysis to support the use of the Sigmoid Formula for dynamic sensitivity determination."
                                                        ).bold()
                                                    }
                                                }
                                            )
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

                if state.dynamicSensitivityType != .disabled {
                    if state.dynamicSensitivityType == .logarithmic {
                        SettingInputSection(
                            decimalValue: $state.adjustmentFactor,
                            booleanValue: $booleanPlaceholder,
                            shouldDisplayHint: $shouldDisplayHint,
                            selectedVerboseHint: Binding(
                                get: { selectedVerboseHint },
                                set: {
                                    selectedVerboseHint = $0.map { AnyView($0) }
                                    hintLabel = String(localized: "Adjustment Factor (AF)")
                                }
                            ),
                            // TODO?: include conditional links to Desmos logarithmic graphs based on which .glucose setting is used
                            units: state.units,
                            type: .decimal("adjustmentFactor"),
                            label: String(localized: "Adjustment Factor (AF)"),
                            miniHint: String(localized: "Alter the rate of Dynamic ISF (Sensitivity) adjustments."),
                            verboseHint:
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Default: 80%").bold()
                                Text(
                                    "The Adjustment Factor (AF) allows you to control how quickly and effectively Dynamic ISF responds to changes in glucose levels."
                                )
                                Text(
                                    "Adjusting this value not only can adjust how quickly your sensitivity will respond to changing glucose readings, but also at what glucose readings you reach your Autosens Max/Min limits."
                                )
                                Text(
                                    "Increasing this setting can make ISF adjustments quicker, but will also change the glucose value that coincides with the ISF used at your Autosens Max and Autosens Min limits. Likewise, decreasing this setting can make ISF adjustments slower and will also change the glucose value that coincides with the ISF used when it reaches the Autosens Max and Autosens Min limits. It is best to utilize the Desmos graphs from TrioDocs.org to optimize all Dynamic Settings."
                                )
                            }
                        )
                    } else {
                        SettingInputSection(
                            decimalValue: $state.adjustmentFactorSigmoid,
                            booleanValue: $booleanPlaceholder,
                            shouldDisplayHint: $shouldDisplayHint,
                            selectedVerboseHint: Binding(
                                get: { selectedVerboseHint },
                                set: {
                                    selectedVerboseHint = $0.map { AnyView($0) }
                                    hintLabel = String(localized: "Sigmoid Adjustment Factor")
                                }
                            ),
                            units: state.units,
                            type: .decimal("adjustmentFactorSigmoid"),
                            label: String(localized: "Sigmoid Adjustment Factor"),
                            miniHint: String(localized: "Alter the rate of dynamic sensitivity adjustments for Sigmoid."),
                            verboseHint:
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Default: 50%").bold()
                                Text(
                                    "The Sigmoid Adjustment Factor (AF) allows you to control how quickly Sigmoid Dynamic ISF responds to changes in glucose levels and at what glucose value you will reach your Autosens Max and Autosens Min limits."
                                )
                                Text(
                                    "Sigmoid Adjustment Factor influences both how fast your ISF values will change and how quickly you will reach your Autosens Max and Min limits set. Increasing Sigmoid Adjustment Factor increases the rate of change of your ISF and reduces the range of glucose values between your Autosens Max and Min limits."
                                )
                                Text(
                                    "This setting allows for a more responsive system, but the effects are restricted by the Autosens Min/Max settings."
                                )
                                Text(
                                    "Due to how the curve is calculated when using the Sigmoid Formula, increasing this setting has a different impact on the steepness of the curve than in the standard logarithmic Dynamic ISF calculation. Use caution when adjusting this setting."
                                )
                            }
                        )
                    }

                    SettingInputSection(
                        decimalValue: $state.weightPercentage,
                        booleanValue: $booleanPlaceholder,
                        shouldDisplayHint: $shouldDisplayHint,
                        selectedVerboseHint: Binding(
                            get: { selectedVerboseHint },
                            set: {
                                selectedVerboseHint = $0.map { AnyView($0) }
                                hintLabel = String(localized: "Weighted Average of TDD")
                            }
                        ),
                        units: state.units,
                        type: .decimal("weightPercentage"),
                        label: String(localized: "Weighted Average of TDD"),
                        miniHint: String(localized: "Weight of 24-hr TDD against 10-day TDD."),
                        verboseHint:
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Default: 35%").bold()
                            Text(
                                "This setting adjusts how much weight is given to your recent total daily insulin dose when calculating Dynamic ISF and Dynamic CR."
                            )
                            Text(
                                "At the default setting, 35% of the calculation is based on the last 24 hours of insulin use, with the remaining 65% considering the last 10 days of data."
                            )
                            Text("Setting this to 100% means only the past 24 hours will be used.")
                            Text("A lower value smooths out these variations for more stability.")
                        }
                    )

                    SettingInputSection(
                        decimalValue: $decimalPlaceholder,
                        booleanValue: $state.tddAdjBasal,
                        shouldDisplayHint: $shouldDisplayHint,
                        selectedVerboseHint: Binding(
                            get: { selectedVerboseHint },
                            set: {
                                selectedVerboseHint = $0.map { AnyView($0) }
                                hintLabel = String(localized: "Adjust Basal")
                            }
                        ),
                        units: state.units,
                        type: .boolean,
                        label: String(localized: "Adjust Basal"),
                        miniHint: String(localized: "Use Dynamic Ratio to adjust basal rates."),
                        verboseHint: VStack(alignment: .leading, spacing: 10) {
                            Text("Default: OFF").bold()
                            Text(
                                "Turn this setting on to give basal adjustments more agility. Keep this setting off if your basal needs are not highly variable."
                            )
                            Text(
                                "Enabling Adjust Basal replaces the standard Autosens Ratio calculation with its own Autosens Ratio calculated as such:"
                            )
                            Text("Autosens Ratio =\n(Weighted Average of TDD) / (10-day Average of TDD)")
                            Text("New Basal Profile =\n(Current Basal Profile) × (Autosens Ratio)")
                        },
                        headerText: String(localized: "Dynamic-dependent Features")
                    )
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
            .navigationBarTitle("Dynamic Settings")
            .navigationBarTitleDisplayMode(.automatic)
        }
    }
}
