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
            Form {
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
                    miniHint: "Allows you to create and save preset meals",
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
                    miniHint: "Percent of bolus used in bolus calculator",
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
                    miniHint: "\"Fatty Meal\" option appears in the bolus calculator",
                    verboseHint:
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Default: OFF").bold()
                        Text("Default Percent: 70%").bold()
                        Text("Do not enable this feature until you have optimized your CR (carb ratio) setting.").bold()
                        Text(
                            "Enabling this setting adds a \"Fatty Meal\" option to the bolus calculator. Once this feature is enabled, a percentage setting will appear below this for you to select."
                        )
                        Text(
                            "When you use a Fatty Meal Bolus, the percentage you select for this setting will replace the Recommended Bolus Percentage setting used in that bolus calculation."
                        )
                        Text(
                            "Tip: This setting should be ↓LOWER↓ than your Recommended Bolus Percentage setting to enable the bolus calculator the ability to give less than the calculated amount to prevent lows due to carbs absorbing very slowly. This could be useful when eating meals like pizza."
                        )
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
                    miniHint: "\"Super Bolus\" option appears in the bolus calculator",
                    verboseHint:
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Default: OFF").bold()
                        Text("Default Percent: 200%").bold()
                        Text("Do not enable this feature until you have optimized your CR (carb ratio) setting.").bold()
                        Text(
                            "Enabling this setting adds a \"Super Bolus\" option to the bolus calculator. Once this feature is enabled, a percentage setting will appear below this for you to select."
                        )
                        Text(
                            "When you use a Super Bolus, the percentage you select for this setting will replace the Recommended Bolus Percentage setting used in that bolus calculation."
                        )
                        Text("The Super Bolus is a useful option for sweet or fast meals.")
                        Text(
                            "Tip: This setting should be ↑HIGHER↑ than your Recommended Bolus Percentage setting to enable the bolus calculator the ability to give above the calculated amount to address carbs that absorb very quickly. This could be useful when eating sweets."
                        )
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
            .navigationBarTitle("Bolus Calculator")
            .navigationBarTitleDisplayMode(.automatic)
        }
    }
}
