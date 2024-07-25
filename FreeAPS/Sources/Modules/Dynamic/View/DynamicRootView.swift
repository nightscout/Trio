import SwiftUI
import Swinject

extension Dynamic {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()
        @State private var showDynamicHint: Bool = false
        @State var hintDetent = PresentationDetent.large

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
            List {
                Section {
                    VStack {
                        Toggle("Activate Dynamic Sensitivity (ISF)", isOn: $state.useNewFormula)

                        HStack {
                            Text(
                                "Trio calculates insulin sensitivity (ISF) each loop cycle based on current blood sugar, daily insulin use, and an adjustment factor, within set limits."
                            ).font(.footnote).foregroundColor(.secondary)
                            Spacer()
                            Button(
                                action: { showDynamicHint.toggle() },
                                label: {
                                    HStack {
                                        Image(systemName: "questionmark.circle")
                                    }
                                }
                            )
                        }
                    }
                }

                if state.useNewFormula {
                    Section {
                        VStack {
                            Toggle("Activate Dynamic Carb Ratio (CR)", isOn: $state.enableDynamicCR)

                            HStack {
                                Text(
                                    "Similar to Dynamic Sensitivity, Trio calculates a dynamic carb ratio every loop cycle."
                                ).font(.footnote).foregroundColor(.secondary)
                                Spacer()
                                Button(
                                    action: { showDynamicHint.toggle() },
                                    label: {
                                        HStack {
                                            Image(systemName: "questionmark.circle")
                                        }
                                    }
                                )
                            }
                        }
                    }
                }

                if state.useNewFormula {
                    Section {
                        HStack {
                            Toggle("Use Sigmoid Formula", isOn: $state.sigmoid)
                        }
                    } header: { Text("Formula") }

                    Section {
                        if !state.sigmoid {
                            HStack {
                                Text("Adjustment Factor")
                                Spacer()
                                TextFieldWithToolBar(text: $state.adjustmentFactor, placeholder: "0", numberFormatter: formatter)
                            }
                        } else {
                            HStack {
                                Text("Sigmoid Adjustment Factor")
                                Spacer()
                                TextFieldWithToolBar(
                                    text: $state.adjustmentFactorSigmoid,
                                    placeholder: "0",
                                    numberFormatter: formatter
                                )
                            }
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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(
                        action: { showDynamicHint.toggle() },
                        label: {
                            HStack {
                                Text("Hints")
                                Image(systemName: "questionmark.circle").font(.system(size: 20))
                            }
                        }
                    )
                }
            }
            .sheet(isPresented: $showDynamicHint) {
                NavigationStack {
                    List {
                        DefinitionRow(
                            term: NSLocalizedString("Enable Dynamic ISF", comment: "Enable Dynamic ISF"),
                            definition: NSLocalizedString(
                                "Calculate a new ISF with every loop cycle. New ISF will be based on current BG, TDD of insulin (past 24 hours or a weighted average) and an Adjustment Factor (default is 1).\n\nDynamic ISF and CR ratios will be limited by your autosens.min/max limits.\n\nDynamic ratio replaces the autosens.ratio:\n\nNew ISF = Static ISF / Dynamic ratio,\n\nDynamic ratio = profile.sens * adjustmentFactor * tdd * Math.log(BG/insulinFactor+1) / 1800,\n\ninsulinFactor = 120 - InsulinPeakTimeInMinutes",
                                comment: "Enable Dynamic ISF"
                            )
                        )
//                        DefinitionRow(
//                            term: NSLocalizedString("Enable Dynamic CR", comment: "Use Dynamic CR together with Dynamic ISF"),
//                            definition: NSLocalizedString(
//                                "Use Dynamic CR. The dynamic ratio will be used for CR as follows:\n\n When ratio > 1:  dynCR = (newRatio - 1) / 2 + 1.\nWhen ratio < 1: dynCR = CR/dynCR.\n\nDon't use toghether with a high Insulin Fraction (> 2)",
//                                comment: "Use Dynamic CR together with Dynamic ISF"
//                            )
//                        )
//                        DefinitionRow(
//                            term: NSLocalizedString("Use Sigmoid Function", comment: "Use Sigmoid Function"),
//                            definition: NSLocalizedString(
//                                "Use a sigmoid function for ISF (and for CR, when enabled), instead of the default Logarithmic formula. Requires the Dynamic ISF setting to be enabled in settings\n\nThe Adjustment setting adjusts the slope of the curve (Y: Dynamic ratio, X: Blood Glucose). A lower value ==> less steep == less aggressive.\n\nThe autosens.min/max settings determines both the max/min limits for the dynamic ratio AND how much the dynamic ratio is adjusted. If AF is the slope of the curve, the autosens.min/max is the height of the graph, the Y-interval, where Y: dynamic ratio. The curve will always have a sigmoid shape, no matter which autosens.min/max settings are used, meaning these settings have big consequences for the outcome of the computed dynamic ISF. Please be careful setting a too high autosens.max value. With a proper profile ISF setting, you will probably never need it to be higher than 1.5\n\nAn Autosens.max limit > 1.5 is not advisable when using the sigmoid function.",
//                                comment: "Use Sigmoid Function"
//                            )
//                        )
                    }
                    .padding(.trailing, 10)
                    .navigationBarTitle("Dynamic ISF Hints", displayMode: .inline)

                    Button { showDynamicHint.toggle() }
                    label: { Text("Got it!").frame(maxWidth: .infinity, alignment: .center) }
                        .buttonStyle(.bordered)
                        .padding(.top)
                }
                .padding()
                .presentationDetents(
                    [.fraction(0.9), .large],
                    selection: $hintDetent
                )
            }
            .onDisappear {
                state.saveIfChanged()
            }
        }
    }
}
