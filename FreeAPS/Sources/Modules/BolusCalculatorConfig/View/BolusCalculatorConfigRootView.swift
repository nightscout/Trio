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
                    miniHint: """
                    Enabling this feature allows you to create and save preset meals
                    Default: OFF
                    """,
                    verboseHint: VStack {
                        Text("Default: OFF").bold()
                        Text("""

                        Enabling this feature allows you to create and save preset meals.
                        """)
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
                    miniHint: """
                    Percentage of the calculated bolus used as your recommended bolus in the bolus calculator
                    Default: 70%
                    """,
                    verboseHint: VStack {
                        Text("Default: 70%").bold()
                        Text("""

                        Recommended bolus percentage is a safety feature built into Trio. Trio first calculates an insulin required value, which is the full dosage. That dosage is then multiplied by your Recommended Bolus Percentage to display your suggested insulin dose in the bolus calculator.

                        Because Trio utilizes SMBs and UAM SMBs to help you reach your target glucose, you'll want this setting to be lower than the full calculated amount (<100%).
                        """)
                        Text("It is not advised to set this to 100% if you also have SMBs and/or UAM SMBs enabled.").italic()
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
                            hintLabel = "Fatty Meal Factor"
                        }
                    ),
                    units: state.units,
                    type: .conditionalDecimal("fattyMealFactor"),
                    label: "Enable Fatty Meal",
                    conditionalLabel: "Fatty Meal Bolus Percentage",
                    miniHint: """
                    Lower your bolus recommendation by this percentage for meals that digest slowly
                    Default: 70%
                    """,
                    verboseHint: VStack {
                        Text("Default: 70%").bold()
                        Text("""

                        This adjustment lowers your calculated bolus by this percentage when you select "Fatty Meal" in the bolus calculator. This setting replaces the Recommended Bolus Percentage Setting when selected.

                        You want this setting to be lower than your Recommended Bolus Percentage setting to prevent lows with meals that digest slowly.
                        """)
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
                            hintLabel = "Super Bolus Percentage"
                        }
                    ),
                    units: state.units,
                    type: .conditionalDecimal("sweetMealFactor"),
                    label: "Enable Super Bolus",
                    conditionalLabel: "Super Bolus Percentage",
                    miniHint: """
                    Raise your bolus recommendation by this percentage for meals with fast carbs
                    Default: 200%
                    """,
                    verboseHint: VStack {
                        Text("Default 200%").bold()
                        Text("""

                        This adjustment raises your calculated bolus by this percentage when you select "Super Bolus" in the bolus calculator. This setting replaces the Recommended Bolus Percentage setting when "Super Bolus" is selected. 

                        You want this setting to be higher than your Recommended Bolus Percentage setting to enable the bolus calculator to give above the calculated amount to address carbs that absorb very quickly. This could be useful when eating sweets.
                        """)
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
