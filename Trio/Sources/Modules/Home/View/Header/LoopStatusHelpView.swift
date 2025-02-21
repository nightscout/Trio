import SwiftUI

struct LoopStatusHelpView: View {
    @Environment(AppState.self) var appState
    @Environment(\.colorScheme) var colorScheme

    var state: Home.StateModel
    var helpSheetDetent: Binding<PresentationDetent>
    var isHelpSheetPresented: Binding<Bool>

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading) {
                Text(
                    "The oref algorithm provides recommendations, showing key variables, decisions on temporary basal rates or super-micro-boluses, and a 'reason' field explaining its actions. Find all key terms of this 'reason' explained below:"
                )
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.top, 50)

                List {
                    DefinitionRow(
                        term: String(localized: "Autosens Ratio"),
                        definition: Text(
                            "The ratio of how sensitive or resistant to insulin you are in the current loop cycle. Baseline = 1.0, Sensitive < 1.0, Resistant > 1.0"
                        ),
                        color: .insulin
                    ).listRowBackground(Color.gray.opacity(0.1))

                    DefinitionRow(
                        term: String(localized: "ISF"),
                        definition: Text(
                            "The first value is your profile Insulin Sensitivity Factor (ISF). The second value, after the arrow, is your adjusted ISF used for the most recent automated dosing calculation."
                        ),
                        color: .insulin
                    ).listRowBackground(Color.gray.opacity(0.1))

                    DefinitionRow(
                        term: String(localized: "COB"),
                        definition: Text(
                            "Amount of Carbs on Board (COB) used in the most recent automated dosing calculation."
                        ),
                        color: .insulin
                    ).listRowBackground(Color.gray.opacity(0.1))

                    DefinitionRow(
                        term: String(localized: "Dev"),
                        definition: Text(
                            "Abbreviation for 'Deviation'. How much the actual glucose change deviated from the BGI."
                        ),
                        color: .insulin
                    ).listRowBackground(Color.gray.opacity(0.1))

                    DefinitionRow(
                        term: String(localized: "BGI"),
                        definition: Text(
                            "The degree to which your glucose should be rising or falling based solely on insulin activity."
                        ),
                        color: .insulin
                    ).listRowBackground(Color.gray.opacity(0.1))

                    DefinitionRow(
                        term: String(localized: "CR"),
                        definition: Text(
                            "The first value is your profile Carb Ratio (CR). The second value, after the arrow, is your adjusted CR used for the most recent automated dosing calculation."
                        ),
                        color: .insulin
                    ).listRowBackground(Color.gray.opacity(0.1))

                    DefinitionRow(
                        term: String(localized: "Target"),
                        definition: Text(
                            "The first value is your target glucose from your settings. The second value, after the arrow, is your adjusted target glucose used for the most recent automated dosing calculation. A second value is shown if you have a temp target, override, or one of the Target Behavior options enabled."
                        ),
                        color: .insulin
                    ).listRowBackground(Color.gray.opacity(0.1))

                    DefinitionRow(
                        term: String(localized: "minPredBG"),
                        definition: Text(
                            "The lowest forecasted value that Trio has estimated for your future glucose."
                        ),
                        color: .insulin
                    ).listRowBackground(Color.gray.opacity(0.1))

                    DefinitionRow(
                        term: String(localized: "minGuardBG"),
                        definition: Text(
                            "The lowest forecasted glucose during the remaining duration of insulin action (DIA)."
                        ),
                        color: .insulin
                    ).listRowBackground(Color.gray.opacity(0.1))

                    DefinitionRow(
                        term: String(localized: "IOBpredBG"),
                        definition: Text(
                            "The forecasted glucose value in 4 hours calculated based on IOB only."
                        ),
                        color: .insulin
                    ).listRowBackground(Color.gray.opacity(0.1))

                    DefinitionRow(
                        term: String(localized: "COBpredBG"),
                        definition: Text(
                            "The forecasted glucose value in 4 hours calculated based on current IOB and COB."
                        ),
                        color: .insulin
                    ).listRowBackground(Color.gray.opacity(0.1))

                    DefinitionRow(
                        term: String(localized: "UAMpredBG"),
                        definition: Text(
                            "The forecasted glucose value in 4 hours based on current deviations ramping down to zero at the same rate they have been recently."
                        ),
                        color: .insulin
                    ).listRowBackground(Color.gray.opacity(0.1))

                    DefinitionRow(
                        term: String(localized: "TDD"),
                        definition: Text(
                            "Abbreviation for 'Total Daily Dose'. Last 24 hours of total insulin administered, both basal and bolus."
                        ),
                        color: .zt
                    ).listRowBackground(Color.gray.opacity(0.1))

                    DefinitionRow(
                        term: String(localized: "Bolus/Basal %"),
                        definition: Text(
                            "Of the total insulin delivered in the past 24 hours, this indicates what percentage was administered through basals and what was given through bolus."
                        ),
                        color: .green
                    ).listRowBackground(Color.gray.opacity(0.1))

                    DefinitionRow(
                        term: String(localized: "Dynamic ISF/CR"),
                        definition: Text(
                            "A display of On/On indicates both Dynamic ISF and CR are enabled. On/Off indicates only Dynamic ISF is enabled. Dynamic CR cannot be enabled when Dynamic ISF is disabled."
                        ),
                        color: .zt
                    ).listRowBackground(Color.gray.opacity(0.1))

                    DefinitionRow(
                        term: String(localized: "Sigmoid function"),
                        definition: Text("If shown, Sigmoid Dynamic ISF is enabled."),
                        color: .zt
                    ).listRowBackground(Color.gray.opacity(0.1))

                    DefinitionRow(
                        term: String(localized: "Logarithmic formula"),
                        definition: Text("If shown, Logarithmic Dynamic ISF is enabled."),
                        color: .zt
                    ).listRowBackground(Color.gray.opacity(0.1))

                    DefinitionRow(
                        term: String(localized: "AF"),
                        definition: Text(
                            "Displays the Adjustment Factor (AF) for either Logathmic or Sigmoid Dynamic ISF in use."
                        ),
                        color: .zt
                    ).listRowBackground(Color.gray.opacity(0.1))

                    DefinitionRow(
                        term: String(localized: "SMB Ratio"),
                        definition: Text(
                            "SMB Delivery Ratio of calculated insulin required that is given as SMB."
                        ),
                        color: .zt
                    ).listRowBackground(Color.gray.opacity(0.1))

                    DefinitionRow(
                        term: String(localized: "Smoothing"),
                        definition: Text("Indicates glucose smoothing is enabled."),
                        color: .gray
                    ).listRowBackground(Color.gray.opacity(0.1))
                }
                .scrollContentBackground(.hidden)
                .navigationBarTitle("Glossary", displayMode: .inline)
                .padding(.bottom, 15)

                Button {
                    isHelpSheetPresented.wrappedValue.toggle()
                } label: {
                    Text("Got it!").bold().frame(maxWidth: .infinity, minHeight: 30, alignment: .center)
                }
                .buttonStyle(.bordered)
                .padding(.top)
            }
            .padding([.horizontal, .bottom])
            .listSectionSpacing(10)
            .ignoresSafeArea(edges: .top)
            .presentationDetents(
                [.fraction(0.9), .large],
                selection: helpSheetDetent
            )
        }
    }

    var legendLinesView: some View {
        Group {
            DefinitionRow(
                term: String(localized: "IOB (Insulin on Board)"),
                definition: Text(
                    "Forecasts future glucose readings based on the amount of insulin still active in the body."
                ),
                color: .insulin
            )

            DefinitionRow(
                term: String(localized: "ZT (Zero-Temp)"),
                definition: Text(
                    "Forecasts the worst-case future glucose reading scenario if no carbs are absorbed and insulin delivery is stopped until glucose starts rising."
                ),
                color: .zt
            )

            DefinitionRow(
                term: String(localized: "COB (Carbs on Board)"),
                definition: Text(
                    "Forecasts future glucose reading changes by considering the amount of carbohydrates still being absorbed in the body."
                ),
                color: .loopYellow
            )

            DefinitionRow(
                term: String(localized: "UAM (Unannounced Meal)"),
                definition: Text(
                    "Forecasts future glucose levels and insulin dosing needs for unexpected meals or other causes of glucose reading increases without prior notice."
                ),
                color: .uam
            )
        }
    }

    var legendConeOfUncertaintyView: some View {
        DefinitionRow(
            term: String(localized: "Cone of Uncertainty"),
            definition: VStack(alignment: .leading, spacing: 10) {
                Text(
                    "For simplicity reasons, oref's various forecast curves are displayed as a \"Cone of Uncertainty\" that depicts a possible, forecasted range of future glucose fluctuation based on the current data and the algothim's result."
                )
                Text(
                    "To modify how the forecast is displayed, go to Settings > Features > User Interface > Forecast Display Type."
                )
            },
            color: Color.blue.opacity(0.5)
        )
    }
}
