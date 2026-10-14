import SwiftUI
import Swinject

extension DynamicISFExplorer {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()

        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState

        private let pickerSettings = PickerSettingsProvider.shared.settings

        private var sensitivityUnit: String {
            state.units == .mgdL ? String(localized: "mg/dL/U") : String(localized: "mmol/L/U")
        }

        var body: some View {
            List {
                Section(
                    content: {
                        if let curve = state.curve {
                            DynamicISFExplorerChart(curve: curve, savedCurve: state.savedCurve, units: state.units)
                                .frame(height: 260)
                                .padding(.vertical)
                        } else {
                            Text(
                                "Dynamic ISF is off for these values. It needs a total daily dose and an Autosens Max above Autosens Min."
                            )
                            .foregroundStyle(.secondary)
                        }
                    },
                    footer: {
                        Text("Starts from your current settings and the last loop. Nothing you change here is saved.")
                    }
                )

                if let activeOverride = state.activeOverride {
                    Section(
                        content: {
                            Toggle("Include Active Override", isOn: $state.includeOverride)
                        },
                        footer: {
                            Text(overrideSummary(activeOverride))
                        }
                    )
                }

                Section(header: Text("Dynamic ISF")) {
                    Picker("Formula", selection: $state.inputs.sigmoid) {
                        Text("Logarithmic").tag(false)
                        Text("Sigmoid").tag(true)
                    }
                    .pickerStyle(.segmented)

                    if state.inputs.sigmoid {
                        factorStepper(
                            String(localized: "Sigmoid Adjustment Factor"),
                            value: $state.inputs.adjustmentFactorSigmoid,
                            setting: pickerSettings.adjustmentFactorSigmoid
                        )
                    } else {
                        factorStepper(
                            String(localized: "Adjustment Factor (AF)"),
                            value: $state.inputs.adjustmentFactor,
                            setting: pickerSettings.adjustmentFactor
                        )
                        stepper(
                            String(localized: "Insulin Peak Time"),
                            value: $state.inputs.insulinPeakTime,
                            in: pickerSettings.insulinPeakTime.min ... pickerSettings.insulinPeakTime.max,
                            step: pickerSettings.insulinPeakTime.step,
                            display: "\(state.inputs.insulinPeakTime) \(String(localized: "min", comment: "Minutes abbreviation"))"
                        )
                    }
                }

                Section(header: Text("Autosens")) {
                    // the loop turns Dynamic ISF off unless Autosens Min ≤ 100% ≤ Autosens Max
                    factorStepper(
                        String(localized: "Autosens Max"),
                        value: $state.inputs.autosensMax,
                        setting: pickerSettings.autosensMax,
                        minimum: 1
                    )
                    factorStepper(
                        String(localized: "Autosens Min"),
                        value: $state.inputs.autosensMin,
                        setting: pickerSettings.autosensMin
                    )
                }

                Section(
                    header: Text("Profile"),
                    footer: Text("Your scheduled values for this time of day.")
                ) {
                    glucoseStepper(
                        String(localized: "Insulin Sensitivity"),
                        value: $state.inputs.sensitivity,
                        in: 9 ... 540,
                        unit: sensitivityUnit
                    )
                    if state.inputs.sigmoid {
                        glucoseStepper(
                            String(localized: "Target Glucose"),
                            value: $state.inputs.target,
                            in: 72 ... 180,
                            unit: state.units.rawValue
                        )
                    }
                }

                Section(
                    header: Text("Total Daily Dose"),
                    footer: Text("Weighted TDD: \(insulin(state.inputs.weightedTDD))")
                ) {
                    stepper(
                        String(localized: "Last 24 Hours"),
                        value: $state.inputs.tddLast24Hours,
                        in: 0 ... 300,
                        step: 1,
                        display: insulin(state.inputs.tddLast24Hours)
                    )
                    stepper(
                        String(localized: "10-Day Average"),
                        value: $state.inputs.tddTenDayAverage,
                        in: 0 ... 300,
                        step: 1,
                        display: insulin(state.inputs.tddTenDayAverage)
                    )
                    factorStepper(
                        String(localized: "Weighted Average of TDD"),
                        value: $state.inputs.weightPercentage,
                        setting: pickerSettings.weightPercentage
                    )
                }
            }
            .listSectionSpacing(sectionSpacing)
            .scrollContentBackground(.hidden).background(appState.trioBackgroundColor(for: colorScheme))
            .onAppear(perform: configureView)
            .navigationTitle("Dynamic ISF Explorer")
            .navigationBarTitleDisplayMode(.automatic)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Reset", action: state.reset)
                        .disabled(!state.hasChanges)
                }
            }
        }

        private func stepper(
            _ title: String,
            value: Binding<Decimal>,
            in range: ClosedRange<Decimal>,
            step: Decimal,
            display: String
        ) -> some View {
            Stepper(value: value, in: range, step: step) {
                LabeledContent(title, value: display)
            }
        }

        private func factorStepper(
            _ title: String,
            value: Binding<Decimal>,
            setting: PickerSetting,
            minimum: Decimal? = nil
        ) -> some View {
            stepper(
                title,
                value: value,
                in: (minimum ?? setting.min) ... setting.max,
                step: setting.step,
                display: "\(value.wrappedValue * 100) \(String(localized: "%", comment: "Percentage symbol"))"
            )
        }

        /// Steps through glucose values in the user's units while the inputs stay in mg/dL.
        private func glucoseStepper(
            _ title: String,
            value: Binding<Decimal>,
            in range: ClosedRange<Decimal>,
            unit: String
        ) -> some View {
            let units = state.units
            let displayed = Binding(
                get: { value.wrappedValue.asUnit(units) },
                set: { value.wrappedValue = units == .mgdL ? $0 : $0.asMgdL }
            )

            return stepper(
                title,
                value: displayed,
                in: range.lowerBound.asUnit(units) ... range.upperBound.asUnit(units),
                step: units == .mgdL ? 1 : 0.1,
                display: "\(displayed.wrappedValue) \(unit)"
            )
        }

        private func insulin(_ value: Decimal) -> String {
            "\(value.formatted(.number.precision(.fractionLength(0 ... 1)))) \(String(localized: "U", comment: "Insulin unit abbreviation"))"
        }

        private func overrideSummary(_ override: ActiveOverride) -> String {
            var parts: [String] = []
            if override.adjustsSensitivity {
                parts.append(String(localized: "\(override.percentage.formatted())% Insulin"))
            }
            if let target = override.target {
                parts.append(String(localized: "Target \(target.formatted(for: state.units)) \(state.units.rawValue)"))
            }
            return parts.joined(separator: ", ")
        }
    }
}
