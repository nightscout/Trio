import SwiftUI
import Swinject

extension DynamicSettings {
    struct RootView: BaseView {
        let resolver: Resolver
        @State var state = StateModel()
        @State private var shouldDisplayHint: Bool = false
        @State var hintDetent = PresentationDetent.large
        @State var selectedVerboseHint: String?
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
                            selectedVerboseHint = $0
                            hintLabel = "Activate Dynamic Sensitivity (ISF)"
                        }
                    ),
                    units: state.units,
                    type: .boolean,
                    label: "Activate Dynamic Sensitivity (ISF)",
                    miniHint: "Trio calculates insulin sensitivity (ISF) each loop cycle based on current blood sugar, daily insulin use, and an adjustment factor, within set limits.",
                    verboseHint: "DynamicISF",
                    headerText: "Dynamic Insulin Sensitivity"
                )

                if state.useNewFormula {
                    SettingInputSection(
                        decimalValue: $decimalPlaceholder,
                        booleanValue: $state.enableDynamicCR,
                        shouldDisplayHint: $shouldDisplayHint,
                        selectedVerboseHint: Binding(
                            get: { selectedVerboseHint },
                            set: {
                                selectedVerboseHint = $0
                                hintLabel = "Activate Dynamic Carb Ratio (CR)"
                            }
                        ),
                        units: state.units,
                        type: .boolean,
                        label: "Activate Dynamic Carb Ratio (CR)",
                        miniHint: "Similar to Dynamic Sensitivity, Trio calculates a dynamic carb ratio every loop cycle.",
                        verboseHint: "Logarithmic Dynamic Insulin Sensitivity"
                    )

                    SettingInputSection(
                        decimalValue: $decimalPlaceholder,
                        booleanValue: $state.sigmoid,
                        shouldDisplayHint: $shouldDisplayHint,
                        selectedVerboseHint: Binding(
                            get: { selectedVerboseHint },
                            set: {
                                selectedVerboseHint = $0
                                hintLabel = "Use Sigmoid Formula"
                            }
                        ),
                        units: state.units,
                        type: .boolean,
                        label: "Use Sigmoid Formula",
                        miniHint: "Alternative formula for dynamic ISF, that alters ISF based on distance from target BG",
                        verboseHint: "Sigmoid  Dynamic Insulin Sensitivity"
                    )

                    if !state.sigmoid {
                        SettingInputSection(
                            decimalValue: $state.adjustmentFactor,
                            booleanValue: $booleanPlaceholder,
                            shouldDisplayHint: $shouldDisplayHint,
                            selectedVerboseHint: Binding(
                                get: { selectedVerboseHint },
                                set: {
                                    selectedVerboseHint = $0
                                    hintLabel = "Adjustment Factor"
                                }
                            ),
                            units: state.units,
                            type: .decimal("adjustmentFactor"),
                            label: "Adjustment Factor",
                            miniHint: "Lorem ipsum dolor sit amet, consetetur sadipscing elitr.",
                            verboseHint: "Adjustment Factor for logarithmic dynamic sensitvity... bla bla bla"
                        )
                    } else {
                        SettingInputSection(
                            decimalValue: $state.adjustmentFactorSigmoid,
                            booleanValue: $booleanPlaceholder,
                            shouldDisplayHint: $shouldDisplayHint,
                            selectedVerboseHint: Binding(
                                get: { selectedVerboseHint },
                                set: {
                                    selectedVerboseHint = $0
                                    hintLabel = "Sigmoid Adjustment Factor"
                                }
                            ),
                            units: state.units,
                            type: .decimal("adjustmentFactorSigmoid"),
                            label: "Sigmoid Adjustment Factor",
                            miniHint: "Lorem ipsum dolor sit amet, consetetur sadipscing elitr.",
                            verboseHint: "Sigmoid Adjustment Factor… should be 0.5… bla bla ba"
                        )
                    }

                    SettingInputSection(
                        decimalValue: $state.weightPercentage,
                        booleanValue: $booleanPlaceholder,
                        shouldDisplayHint: $shouldDisplayHint,
                        selectedVerboseHint: Binding(
                            get: { selectedVerboseHint },
                            set: {
                                selectedVerboseHint = $0
                                hintLabel = "Weighted Average of TDD"
                            }
                        ),
                        units: state.units,
                        type: .decimal("weightPercentage"),
                        label: "Weighted Average of TDD",
                        miniHint: "Lorem ipsum dolor sit amet, consetetur sadipscing elitr.",
                        verboseHint: "Weight of past 24 hours"
                    )

                    SettingInputSection(
                        decimalValue: $decimalPlaceholder,
                        booleanValue: $state.tddAdjBasal,
                        shouldDisplayHint: $shouldDisplayHint,
                        selectedVerboseHint: Binding(
                            get: { selectedVerboseHint },
                            set: {
                                selectedVerboseHint = $0
                                hintLabel = "Adjust Basal"
                            }
                        ),
                        units: state.units,
                        type: .boolean,
                        label: "Adjust Basal",
                        miniHint: "Lorem ipsum dolor sit amet, consetetur sadipscing elitr.",
                        verboseHint: "Adjust basal dynamically… bla bla"
                    )

                    SettingInputSection(
                        decimalValue: $state.threshold_setting,
                        booleanValue: $booleanPlaceholder,
                        shouldDisplayHint: $shouldDisplayHint,
                        selectedVerboseHint: Binding(
                            get: { selectedVerboseHint },
                            set: {
                                selectedVerboseHint = $0
                                hintLabel = "Minimum Safety Threshold"
                            }
                        ),
                        units: state.units,
                        type: .decimal("threshold_setting"),
                        label: "Minimum Safety Threshold",
                        miniHint: "Lorem ipsum dolor sit amet, consetetur sadipscing elitr.",
                        verboseHint: "Minimum Safety Threshold… bla bla bla"
                    )
                }
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
            .navigationBarTitle("Dynamic Settings")
            .navigationBarTitleDisplayMode(.automatic)
            .onDisappear {
                state.saveIfChanged()
            }
        }
    }
}
