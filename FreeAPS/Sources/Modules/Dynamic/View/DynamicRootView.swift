import SwiftUI
import Swinject

extension Dynamic {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()

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
            if state.unit == .mmolL {
                formatter.maximumFractionDigits = 1
            } else { formatter.maximumFractionDigits = 0 }
            formatter.roundingMode = .halfUp
            return formatter
        }

        var body: some View {
            Form {
                Section {
                    HStack {
                        Toggle("Activate Dynamic Sensitivity (ISF)", isOn: $state.useNewFormula)
                    }
                    if state.useNewFormula {
                        HStack {
                            Toggle("Activate Dynamic Carb Ratio (CR)", isOn: $state.enableDynamicCR)
                        }
                    }
                } header: { Text("Enable") }

                if state.useNewFormula {
                    Section {
                        HStack {
                            Toggle("Use Sigmoid Formula", isOn: $state.sigmoid)
                        }
                    } header: { Text("Formula") }

                    Section {
                        HStack {
                            Text("Adjustment Factor")
                            Spacer()
                            TextFieldWithToolBar(text: $state.adjustmentFactor, placeholder: "0", numberFormatter: formatter)
                        }

                        HStack {
                            Text("Weighted Average of TDD. Weight of past 24 hours:")
                            Spacer()
                            TextFieldWithToolBar(text: $state.weightPercentage, placeholder: "0", numberFormatter: formatter)
                        }

                        HStack {
                            Toggle("Adjust basal", isOn: $state.tddAdjBasal)
                        }
                    } header: { Text("Settings") }

                    Section {
                        HStack {
                            Text("Threshold Setting")
                            Spacer()
                            TextFieldWithToolBar(
                                text: $state.threshold_setting,
                                placeholder: "0",
                                numberFormatter: glucoseFormatter
                            )
                            Text(state.unit.rawValue)
                        }
                    } header: { Text("Safety") }
                }
            }
            .scrollContentBackground(.hidden).background(color)
            .onAppear(perform: configureView)
            .navigationBarTitle("Dynamic ISF")
            .navigationBarTitleDisplayMode(.automatic)
            .onDisappear {
                state.saveIfChanged()
            }
        }
    }
}
