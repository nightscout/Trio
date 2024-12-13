import SwiftUI
import Swinject

extension BolusCalculatorConfig {
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

        private var conversionFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 1

            return formatter
        }

        private var formatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            return formatter
        }

        var body: some View {
            List {
                SettingInputSection(
                    decimalValue: $decimalPlaceholder,
                    booleanValue: $state.displayPresets,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = "Display Meal Presets"
                        }
                    ),
                    units: state.units,
                    type: .boolean,
                    label: "Display Meal Presets",
                    miniHint: "Allows you to create and save preset meals.",
                    verboseHint: VStack(alignment: .leading, spacing: 10) {
                        Text("Default: ON").bold()
                        Text("Enabling this feature allows you to create and save preset meals.")
                    }
                )

                SettingInputSection(
                    decimalValue: $state.overrideFactor,
                    booleanValue: $booleanPlaceholder,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = "Recommended Bolus Percentage"
                        }
                    ),
                    units: state.units,
                    type: .decimal("overrideFactor"),
                    label: "Recommended Bolus Percentage",
                    miniHint: "Percentage of bolus used in bolus calculator.",
                    verboseHint:
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Default: 80%").bold()
                        Text(
                            "Recommended Bolus Percentage is a safety feature built into Trio. Trio first calculates an insulin required value, which is the full dosage. That dosage is then multiplied by your Recommended Bolus Percentage to display your suggested insulin dose in the bolus calculator."
                        )
                        Text(
                            "Because Trio utilizes SMBs and UAM SMBs to help you reach your target glucose, this is initially set to below the full calculated amount (<100%) because other AID systems do not bolus for COB the same way Trio does. When SMBs and UAM SMBs are enabled, you may find your current CR results in lows and needs to be increased before you increase this setting closer to or at 100%."
                        )
                        Text(
                            "Tip: If you are a new Trio user, it is not advised to set this to 100% until you have verified that your core settings (basal rates, ISF, and CR) do not need adjusting."
                        )
                    },
                    headerText: "Calculator Configuration"
                )

                SettingInputSection(
                    decimalValue: $state.fattyMealFactor,
                    booleanValue: $state.fattyMeals,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = "Fatty Meal"
                        }
                    ),
                    units: state.units,
                    type: .conditionalDecimal("fattyMealFactor"),
                    label: "Enable Fatty Meal Option",
                    conditionalLabel: "Fatty Meal Bolus Percentage",
                    miniHint: "Adds a \"Fatty Meal\" option to the bolus calculator.",
                    verboseHint:
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Default: OFF").bold()
                        Text("Default Percent: 70%").bold()
                        Text("Do not enable this feature until you have optimized your CR (carb ratio) setting.").bold()
                        Text(
                            "Enabling this setting adds a \"Fatty Meal\" option to the bolus calculator. Once this feature is enabled, a percentage setting will appear for you to select."
                        )
                        Text(
                            "When \"Fatty Meal\" is selected in the bolus calculator, the recommended bolus will be multiplied by the \"Fatty Meal Bolus Percentage\" as well as the \"Recommended Bolus Percentage\"."
                        )
                        Text(
                            "If you have a \"Recommended Bolus Percentage\" of 80%, and a \"Fatty Meal Bolus Percentage\" of 70%, your recommended bolus will be multiplied by: (80 × 70) ÷ 100 = 56%."
                        )
                        Text("This could be useful for slow absorbing meals like pizza.")
                    }
                )

                SettingInputSection(
                    decimalValue: $state.sweetMealFactor,
                    booleanValue: $state.sweetMeals,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = "Super Bolus"
                        }
                    ),
                    units: state.units,
                    type: .conditionalDecimal("sweetMealFactor"),
                    label: "Enable Super Bolus Option",
                    conditionalLabel: "Super Bolus Percentage",
                    miniHint: "Adds a \"Super Bolus\" option to the bolus calculator.",
                    verboseHint:
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Default: OFF").bold()
                        Text("Default Percent: 200%").bold()
                        Text("Do not enable this feature until you have optimized your CR (carb ratio) setting.").bold()
                        Text(
                            "Enabling this setting adds a \"Super Bolus\" option to the bolus calculator. Once this feature is enabled, a percentage setting will appear for you to select."
                        )
                        Text(
                            "When \"Super Bolus\" is selected in the bolus calculator, your current basal rate multiplied by \"Super Bolus Percentage\" will be added to your bolus recommendation."
                        )
                        Text(
                            "If your current basal rate is 0.8 U/hr and \"Super Bolus Percentage\" is set to 200%: 0.8 × (200 ÷ 100) = 1.6 units will be added to your bolus recommendation."
                        )
                        Text("This could be useful for fast absorbing meals like sugary cereal.")
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
            .scrollContentBackground(.hidden).background(appState.trioBackgroundColor(for: colorScheme))
            .onAppear(perform: configureView)
            .navigationBarTitle("Bolus Calculator")
            .navigationBarTitleDisplayMode(.automatic)
        }
    }
}
