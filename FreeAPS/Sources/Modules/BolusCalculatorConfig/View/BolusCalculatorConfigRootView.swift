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
                    miniHint: "Lorem ipsum dolor sit amet, consetetur sadipscing elitr.",
                    verboseHint: Text("Lorem ipsum dolor sit amet, consetetur sadipscing elitr.")
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
                    miniHint: "Lorem ipsum dolor sit amet, consetetur sadipscing elitr.",
                    verboseHint: Text("Recommended Bolus Percentage… bla bla bla"),
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
                    label: "Enable Fatty Meal Factor",
                    conditionalLabel: "Fatty Meal Factor",
                    miniHint: "Lower your bolus recommendation by factor x for fatty meals.",
                    verboseHint: Text(
                        "You can add the option in your bolus calculator to apply another (!) customizable factor at the end of the calculation which could be useful for fatty meals, e.g Pizza (default 0.7)."
                    )
                )

                SettingInputSection(
                    decimalValue: $state.sweetMealFactor,
                    booleanValue: $state.sweetMeals,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = "Super Bolus & Sweet Meal Factor"
                        }
                    ),
                    units: state.units,
                    type: .conditionalDecimal("sweetMealFactor"),
                    label: "Enable Super Bolus",
                    conditionalLabel: "Super Bolus Factor",
                    miniHint: "Add x times current scheduled basal rate to your bolus recommendation.",
                    verboseHint: Text(
                        "You can enable the super bolus functionality which could be useful when eating sweets/cake etc. Therefore your current basal rate will be added x-times to your bolus recommendation. You can adjust the factor X here, the default is 2 times your current scheduled basal rate."
                    )
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
