import SwiftUI
import Swinject

extension DynamicSettings {
    struct RootView: BaseView {
        let resolver: Resolver
        @State var state = StateModel()
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
                SettingInputSection(
                    decimalValue: $decimalPlaceholder,
                    booleanValue: $state.useNewFormula,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = "Activate Dynamic Sensitivity (ISF)"
                        }
                    ),
                    units: state.units,
                    type: .boolean,
                    label: "Activate Dynamic ISF",
                    miniHint: "Adjusts ISF dynamically based on recent BG and insulin \nDefault: OFF",
                    verboseHint: VStack(spacing: 10) {
                        Text("Default: OFF").bold()
                        VStack(alignment: .leading, spacing: 10) {
                            Text(
                                "Enabling this feature allows Trio to calculate a new Insulin Sensitivity Factor (ISF) with each loop cycle by considering your current glucose (BG), total daily dose (TDD) of insulin, and adjustment factor (AF). This helps tailor your insulin response more accurately in real-time."
                            )
                            Text(
                                "Dynamic ISF produces a Dynamic Ratio, replacing the Autosens Ratio, determining how much your profile ISF will be adjusted every loop cycle, ensuring it stays within safe limits set by your Autosens Min/Max settings. It provides more precise insulin dosing by responding to changes in insulin needs throughout the day."
                            )
                            VStack(alignment: .leading, spacing: 10) {
                                Text("New ISF = (Profile ISF) ÷ (Dynamic Ratio)").italic()
                                Text("Dynamic Ratio = (Profile ISF) × AF × TDD × (log(BG ÷ (Insulin Factor) + 1)) ÷ 1800")
                                    .italic()
                                Text("Insulin Factor = 120 - (Insulin Peak Time)").italic()
                            }
                        }
                    },
                    headerText: "Dynamic Settings"
                )

                if state.useNewFormula {
                    SettingInputSection(
                        decimalValue: $decimalPlaceholder,
                        booleanValue: $state.enableDynamicCR,
                        shouldDisplayHint: $shouldDisplayHint,
                        selectedVerboseHint: Binding(
                            get: { selectedVerboseHint },
                            set: {
                                selectedVerboseHint = $0.map { AnyView($0) }
                                hintLabel = "Activate Dynamic CR (Carb Ratio)"
                            }
                        ),
                        units: state.units,
                        type: .boolean,
                        label: "Activate Dynamic CR (Carb Ratio)",
                        miniHint: "Dynamically adjusts carb ratio (CR)\nDefault: OFF",
                        verboseHint: VStack(spacing: 10) {
                            Text("Default: OFF").bold()
                            VStack(alignment: .leading, spacing: 10) {
                                Text(
                                    "Dynamic CR adjusts your carb ratio based on your Dynamic Ratio, adapting automatically to changes in insulin sensitivity."
                                )
                                Text(
                                    "When Dynamic Ratio increases, indicating you need more insulin, the carb ratio is adjusted to make your insulin dosing more effective."
                                )
                                Text(
                                    "When Dynamic Ratio decreases, indicating you need less insulin, the carb ratio is scaled back to avoid over-delivery."
                                )
                                Text(
                                    "Note: It’s recommended not to use this feature with a high Insulin Fraction (>2), as it can cause insulin dosing to become too aggressive."
                                )
                                .italic()
                            }
                        }
                    )

                    SettingInputSection(
                        decimalValue: $decimalPlaceholder,
                        booleanValue: $state.sigmoid,
                        shouldDisplayHint: $shouldDisplayHint,
                        selectedVerboseHint: Binding(
                            get: { selectedVerboseHint },
                            set: {
                                selectedVerboseHint = $0.map { AnyView($0) }
                                hintLabel = "Use Sigmoid Formula"
                            }
                        ),
                        units: state.units,
                        type: .boolean,
                        label: "Use Sigmoid Formula",
                        miniHint: "Adjusts ISF using a sigmoid-shaped curve \nDefault: OFF",
                        verboseHint: VStack(spacing: 10) {
                            Text("Default: OFF").bold()
                            VStack(alignment: .leading, spacing: 10) {
                                Text(
                                    "Turning on the Sigmoid Formula setting alters how your Dynamic Ratio, and thus your New ISF and New Carb Ratio, are calculated using a sigmoid curve rather than the default logarithmic function. The curve's steepness is influenced by the Adjustment Factor (AF), while the Autosens Min/Max settings determine the limits of the ratio adjustment, which can also influence the steepness of the sigmoid curve."
                                )
                                Text(
                                    "When using the Sigmoid Formula, TDD has a much lower impact on the dynamic adjustments to sensitivity."
                                )
                                Text("Careful tuning is essential to avoid overly aggressive insulin changes.")
                                Text("It is not recommended to set Autosens Max above 150% to maintain safe insulin dosing.")
                                    .italic()
                                Text(
                                    "There has been no empirical data analysis to support the use of the Sigmoid Formula for dynamic sensitivity determination."
                                )
                                .italic().bold()
                            }
                        }
                    )

                    if !state.sigmoid {
                        SettingInputSection(
                            decimalValue: $state.adjustmentFactor,
                            booleanValue: $booleanPlaceholder,
                            shouldDisplayHint: $shouldDisplayHint,
                            selectedVerboseHint: Binding(
                                get: { selectedVerboseHint },
                                set: {
                                    selectedVerboseHint = $0.map { AnyView($0) }
                                    hintLabel = "Adjustment Factor (AF)"
                                }
                            ),
                            units: state.units,
                            type: .decimal("adjustmentFactor"),
                            label: "Adjustment Factor (AF)",
                            miniHint: "Influences the rate of dynamic sensitivity adjustments \nDefault: 80%",
                            verboseHint: VStack(spacing: 10) {
                                Text("Default: 80%").bold()
                                VStack(alignment: .leading, spacing: 10) {
                                    Text(
                                        "The Adjustment Factor (AF) allows you to control how quickly and effectively Dynamic ISF responds to changes in blood glucose levels."
                                    )
                                    Text(
                                        "Adjusting this value not only can adjust how quickly your sensitivity will respond to changing glucose readings, but also at what glucose readings you reach your Autosens Max/Min limits."
                                    )
                                    Text(
                                        "Warning: Increasing this setting too high can result in a much lower ISF used at your target glucose than your profile ISF. Decreasing this setting too low can result in a much higher ISF used at your target glucose. It is best to utilize the Desmos graphs from the Trio Docs to optimize all Dynamic Settings."
                                    )
                                    .bold().italic()
                                }
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
                                    hintLabel = "Sigmoid Adjustment Factor"
                                }
                            ),
                            units: state.units,
                            type: .decimal("adjustmentFactorSigmoid"),
                            label: "Sigmoid Adjustment Factor",
                            miniHint: "Influences the rate of dynamic sensitivity adjustments for Sigmoid \nDefault: 50%",
                            verboseHint: VStack(spacing: 10) {
                                Text("Default: 50%").bold()
                                VStack(alignment: .leading, spacing: 10) {
                                    Text(
                                        "The Sigmoid Adjustment Factor (AF) allows you to control how quickly Dynamic ISF using Sigmoid Formula responds to changes in blood glucose levels."
                                    )
                                    Text(
                                        "Higher values lead to quicker adjustment responses for high or low blood glucose levels by making the sigmoid-shaped adjustment curve steeper."
                                    )
                                    Text(
                                        "This setting allows for a more responsive system, but the effects are restricted by the Autosens Min/Max settings."
                                    )
                                    Text(
                                        "Due to how the curve is calculated when using the Sigmoid Formula, increasing this setting has a different impact on the steepness of the curve than in the standard logarithmic Dynamic ISF calculation. Use caution when adjusting this setting."
                                    )
                                    .italic()
                                }
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
                                hintLabel = "Weighted Average of TDD"
                            }
                        ),
                        units: state.units,
                        type: .decimal("weightPercentage"),
                        label: "Weighted Average of TDD",
                        miniHint: "Weight of 24-hr TDD against 10-day TDD \nDefault: 65%",
                        verboseHint: VStack(spacing: 10) {
                            Text("Default: 65%").bold()
                            VStack(alignment: .leading, spacing: 10) {
                                Text(
                                    "This setting adjusts how much weight is given to your recent total daily insulin dose (TDD) when calculating Dynamic ISF and Dynamic CR."
                                )
                                Text(
                                    "At the default setting, 65% of the calculation is based on the last 24 hours of insulin use, with the remaining 35% considering the last 10 days of data."
                                )
                                Text("Setting this to 100% means only the past 24 hours will be used.")
                                Text("A lower value smooths out these variations for more stability.")
                            }
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
                                hintLabel = "Adjust Basal"
                            }
                        ),
                        units: state.units,
                        type: .boolean,
                        label: "Adjust Basal",
                        miniHint: "Use Dynamic Ratio to adjust basal rates \nDefault: OFF",
                        verboseHint: VStack(spacing: 10) {
                            Text("Default: OFF").bold()
                            Text("""

                            Turn this setting on to give basal adjustments more agility. Keep this setting off if your basal needs are not highly variable.

                            Normally, a new basal rate is set by autosens:

                            """)
                            Text("New Basal Profile = (Current Basal Profile) x (Autosens Ratio)").italic()
                            Text("""

                            Adjust Basal replaces the standard Autosens Ratio calculation with its own Autosens Ratio calculated as such:

                            """)
                            Text("""
                            Autosens Ratio = (Weighted Average of TDD) ÷ (10-day Average of TDD)

                            New Basal Profile = (Current Basal Profile) × (Autosens Ratio)
                            """).italic()
                        }
                    )

                    SettingInputSection(
                        decimalValue: $state.threshold_setting,
                        booleanValue: $booleanPlaceholder,
                        shouldDisplayHint: $shouldDisplayHint,
                        selectedVerboseHint: Binding(
                            get: { selectedVerboseHint },
                            set: {
                                selectedVerboseHint = $0.map { AnyView($0) }
                                hintLabel = "Minimum Safety Threshold"
                            }
                        ),
                        units: state.units,
                        type: .decimal("threshold_setting"),
                        label: "Minimum Safety Threshold",
                        miniHint: "Increase the safety threshold used to suspend insulin delivery \nDefault: 60 (Set by Algorithm)",
                        verboseHint: VStack(spacing: 10) {
                            Text("Default: Set by Algorithm").bold()
                            VStack(alignment: .leading, spacing: 10) {
                                Text(
                                    "Minimum Threshold Setting is, by default, determined by your set Target Glucose. This threshold automatically suspends insulin delivery if your glucose levels are forecasted to fall below this value. It’s designed to protect against hypoglycemia, particularly during sleep or other vulnerable times."
                                )
                                Text(
                                    "Trio will use the larger of the default setting calculation below and the value entered here."
                                )
                                VStack(alignment: .leading, spacing: 10) {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text("The default setting is based on this calculation:").bold()
                                        Text("Target BG - 0.5 × (Target BG - 40)").italic()
                                    }
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(
                                            "If your glucose target is 110 mg/dL, Trio will use a safety threshold of 75 mg/dL, unless you set Minimum Safety Threshold (mg/dL) to something > 75."
                                        )
                                        Text("110 - 0.5 × (110 - 40) = 75").italic()
                                    }
                                    Text("This setting is limited to values between 60 - 120 mg/dL (3.3 - 6.6 mmol/L)")
                                    Text(
                                        "Note: Basal may be resumed if there's negative IOB and glucose is rising faster than the forecast."
                                    )
                                    .italic()
                                }
                            }
                        }
                    )
                }
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
            .navigationBarTitle("Dynamic Settings")
            .navigationBarTitleDisplayMode(.automatic)
            .onDisappear {
                state.saveIfChanged()
            }
        }
    }
}
