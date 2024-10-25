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
                    label: "Activate Dynamic ISF (Sensitivity)",
                    miniHint: """
                    When enabled, Trio adjusts your Insulin Sensitivity Factor (ISF) automatically based on blood glucose, insulin use, and an adjustment factor
                    Default: OFF
                    """,
                    verboseHint: VStack {
                        Text("Default: OFF").bold()
                        Text("""

                        Dynamic ISF allows Trio to calculate a new ISF with each loop cycle by considering your current blood glucose (BG), total daily dose (TDD) of insulin, and adjustment factor (AF). This helps tailor your insulin response more accurately in real-time. 

                        Dynamic ISF calculates a Dynamic Ratio, determining how much your profile ISF will be adjusted every loop cycle, ensuring it stays within safe limits set by your Autosens Min/Max settings. It provides more precise insulin dosing by responding to changes in insulin needs throughout the day.
                        """)
                        Text("""

                         Dynamic Ratio = (Profile ISF) × AF × TDD × (log(BG ÷ (Insulin Factor) + 1)) ÷ 1800

                         New ISF = (Profile ISF) ÷ (Dynamic Ratio)

                         Insulin Factor = 120 - (Insulin Peak Time)
                        """).italic()
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
                        miniHint: """
                        Automatically adjust your carb ratio (CR) based on insulin sensitivity and glucose levels
                        Default: OFF
                        """,
                        verboseHint: VStack {
                            Text("Default: OFF").bold()
                            Text("""

                            Dynamic CR adjusts your carb ratio (CR) in real-time, depending on your Dynamic Ratio. When this ratio increases (indicating you need more insulin), the CR is adjusted to make your insulin dosing more effective. When the ratio decreases (indicating you need less insulin), the carb ratio is scaled back to avoid over-delivery.

                            """)
                            Text(
                                "It’s recommended not to use this feature with a high Insulin Fraction (>2), as it can cause insulin dosing to become too aggressive."
                            )
                            .italic()
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
                        miniHint: """
                        Alternative formula for Dynamic ISF (Sensitivity), that adjusts ISF based on distance from target BG using a sigmoid-shaped curve
                        Default: OFF
                        """,
                        verboseHint: VStack {
                            Text("Default: OFF").bold()
                            Text("""

                            Turning on the Sigmoid Formula setting changes how your Dynamic Ratio, and thus your New ISF and New Carb Ratio, are calculated using a sigmoid curve rather than the default logarithmic function. The curve's steepness is adjusted by the Adjustment Factor (AF), while the Autosens Min/Max settings determine the limits of the ratio adjustment. 

                            When using the Sigmoid Formula, TDD has a much lower impact on the dynamic adjustments to sensitivity.

                            Careful tuning is essential to avoid overly aggressive insulin changes.

                            """)
                            Text("""
                            It is not recommended to set Autosens Max above 150% to maintain safe insulin dosing.

                            """).italic()
                            Text("There has been no empirical data analysis to support the use of the Sigmoid Formula for dynamic sensitivity determination.").italic()
                                .bold()
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
                            miniHint: """
                            Fine-tune how aggressively your ISF changes in response to glucose fluctuations when using Dynamic ISF (logarithmic formula)
                            Default: 80%
                            """,
                            verboseHint: VStack {
                                Text("Default: 80%").bold()
                                Text("""

                                The Adjustment Factor (AF) allows you to control how aggressively your dynamic ISF responds to changes in blood glucose levels. 

                                A higher value means a stronger correction, increasing or decreasing the sensitivity of your insulin delivery to highs and lows in your glucose readings.

                                """)
                                Text("The maximum effect of this setting is limited by the Autosens Min/Max values.").italic()
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
                            miniHint: """
                            Fine-tune how aggressively your ISF changes in response to glucose fluctuations when using Sigmoid Formula for Dynamic ISF
                            Default: 50%
                            """,
                            verboseHint: VStack {
                                Text("Default: 50%").bold()
                                Text("""

                                The Sigmoid Adjustment Factor (AF) allows you to control how aggressively your Dynamic ISF using the Sigmoid Formula responds to changes in blood glucose levels. 

                                Higher values lead to stronger corrections for high or low blood glucose levels, making the curve steeper. 

                                This setting allows for a more responsive system, but like other dynamic settings, its effect is capped by the Autosens Min/Max limits.

                                """)
                                Text(
                                    "Due to how the curve is calculated when using the Sigmoid Formula, increasing this setting has a greater impact on the steepness of the curve than in the standard logarithmic Dynamic ISF calculation. Use caution when adjusting this setting."
                                )
                                .italic()
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
                        miniHint: """
                        The weight of the last 24 hours of total daily insulin dose (TDD) to calculate the Autosens Ratio used in Dynamic ISF and Dynamic CR
                        Default: 65%
                        """,
                        verboseHint: VStack {
                            Text("Default: 65%").bold()
                            Text("""

                            This setting adjusts how much weight is given to your recent total daily insulin dose (TDD) when calculating Dynamic ISF and Dynamic CR. 

                            At the default setting, 65% of the calculation is based on the last 24 hours of insulin use, with the remaining 35% considering the last 10 days of data. 

                            Setting this to 100% means only the past 24 hours will be used. 

                            A lower value smooths out these variations for more stability.
                            """)
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
                        miniHint: """
                        Replaces Autosens’s formula for adjusting basal rates, with a formula dependent on total daily dose (TDD) of insulin.
                        Default: OFF
                        """,
                        verboseHint: VStack {
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
                        miniHint: """
                        This gives you the ability to increase the threshold in which insulin delivery stops.
                        Default: (Set by Algorithm)
                        """,
                        verboseHint: VStack {
                            Text("Default: Set by Algorithm").bold()
                            Text("""

                            Minimum Threshold Setting is determined by your set Target Glucose. This threshold automatically suspends insulin delivery if your glucose levels are forecasted to fall below this value. It’s designed to protect against hypoglycemia, particularly during sleep or other vulnerable times.

                            If your glucose target is 110 mg/dL, Trio will use a safety threshold of 75 mg/dL, unless you set Minimum Safety Threshold (mg/dL) to something > 75.

                            If you leave Minimum Safety Threshold at the default, then it will use the safety threshold calculated by the algorithm that depends on your target. The lower you set your target, the lower the safety threshold will get set. If you don't want to allow it to set your safety threshold below a certain value, you can raise Minimum Safety Threshold to a higher value using this setting.

                            """)
                            Text("Basal may be resumed if there's negative IOB and glucose is rising faster than the forecast.")
                                .italic()
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
