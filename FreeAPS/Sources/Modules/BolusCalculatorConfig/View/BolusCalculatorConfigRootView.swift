import SwiftUI
import Swinject

extension BolusCalculatorConfig {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()

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
                Section {
                    HStack {
                        Toggle("Use alternate Bolus Calculator", isOn: $state.useCalc)
                    }

                    if state.useCalc {
                        HStack {
                            Text("Override With A Factor Of ")
                            Spacer()
                            TextFieldWithToolBar(
                                text: $state.overrideFactor,
                                placeholder: "0.8",
                                numberFormatter: conversionFormatter
                            )
                        }
                    }

                    if !state.useCalc {
                        HStack {
                            Text("Recommended Bolus Percentage")
                            TextFieldWithToolBar(text: $state.insulinReqPercentage, placeholder: "", numberFormatter: formatter)
                        }
                    }
                } header: { Text("Calculator settings") }

                Section {
                    Toggle("Display Presets", isOn: $state.displayPresets)

                } header: { Text("Smaller iPhone Screens") }

                if state.useCalc {
                    Section {
                        HStack {
                            Toggle("Apply factor for fatty meals", isOn: $state.fattyMeals)
                        }
                        HStack {
                            Text("Override With A Factor Of ")
                            Spacer()
                            TextFieldWithToolBar(
                                text: $state.fattyMealFactor,
                                placeholder: "0.7",
                                numberFormatter: conversionFormatter
                            )
                        }
                    } header: { Text("Fatty Meals") }

                    Section {
                        HStack {
                            Toggle("Enable super bolus", isOn: $state.sweetMeals)
                        }
                        HStack {
                            Text("Factor how often current basalrate is added")
                            Spacer()
                            TextFieldWithToolBar(
                                text: $state.sweetMealFactor,
                                placeholder: "2",
                                numberFormatter: conversionFormatter
                            )
                        }
                    } header: { Text("Sweet Meals") }

                    Section {}
                    footer: { Text(
                        "The new alternate bolus calculator is another approach to the default bolus calculator in iAPS. If the toggle is on you use this bolus calculator and not the original iAPS calculator. At the end of the calculation a custom factor is applied as it is supposed to be when using smbs (default 0.8).\n\nYou can also add the option in your bolus calculator to apply another (!) customizable factor at the end of the calculation which could be useful for fatty meals, e.g Pizza (default 0.7).\n\nMoreover you can enable the super bolus functionality which could be useful when eating sweets/cake etc. Therefore your current basal rate will be added x-times to you your bolus recommendation. You can adjust x here, the default is 2 times your current basal rate."
                    )
                    }
                }
            }
            .scrollContentBackground(.hidden).background(color)
            .onAppear(perform: configureView)
            .navigationBarTitle("Bolus Calculator")
            .navigationBarTitleDisplayMode(.automatic)
        }
    }
}
