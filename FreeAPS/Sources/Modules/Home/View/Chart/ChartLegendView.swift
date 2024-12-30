import SwiftUI

struct ChartLegendView: View {
    @Environment(AppState.self) var appState
    @Environment(\.colorScheme) var colorScheme

    var state: Home.StateModel

    @State var legendSheetDetent = PresentationDetent.large

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading) {
                Text(
                    "The main chart in Trio is made up of various elements and shapes. Find their meanings below."
                )
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.top, 50)

                List {
                    VStack(alignment: .leading) {
                        Text("Forecasts").bold().padding(.bottom, 5).textCase(.uppercase)
                        Text(
                            "The oref algorithm determines insulin dosing based on a number of scenarios that it estimates with different types of forecasts."
                        )
                        .font(.subheadline)
                        .foregroundColor(.primary)

                        if state.forecastDisplayType == .lines {
                            legendLinesView
                        } else {
                            legendConeOfUncertaintyView
                        }
                    }.listRowBackground(Color.gray.opacity(0.1))

                    VStack(alignment: .leading) {
                        Text("Other Elements & Shapes").bold().padding(.bottom, 5).textCase(.uppercase)

                        DefinitionRow(
                            term: "CGM Glucose Value",
                            definition: Text(
                                "Displays real-time glucose readings from a Continuous Glucose Monitor (CGM). Depending on your user interface settings, this may be displayed in a static (red, green, orange) or dynamic coloring scheme (full color spectrum)."
                            ),
                            color: Color.green,
                            iconString: !state.settingsManager.settings.smoothGlucose ? "circle.fill" : "record.circle.fill"
                        )

                        DefinitionRow(
                            term: "Manual Glucose Measurement",
                            definition: Text("Manually entered blood glucose, such as a fingerstick test."),
                            color: Color.red,
                            iconString: "drop.fill"
                        )

                        DefinitionRow(
                            term: "Bolus",
                            definition: Text(
                                "Shows an insulin dose, which can be a small automated dose (super-micro-bolus), a manually entered dose, or one given externally (e.g., a pen shot)."
                            ),
                            color: Color.insulin,
                            iconString: "arrowtriangle.down.fill"
                        )

                        DefinitionRow(
                            term: "Carb Entry",
                            definition: Text("Tracks the carbohydrates you eat, entered to guide insulin dosing."),
                            color: Color.orange,
                            iconString: "arrowtriangle.down.fill",
                            shouldRotateIcon: true
                        )

                        DefinitionRow(
                            term: "Fat-Protein Carb Equivalent",
                            definition: Text(
                                "Represents carb equivalent for fat and protein, calculated using the Warsaw Method"
                            ),
                            color: Color.brown,
                            iconString: "circle.fill"
                        )

                        DefinitionRow(
                            term: "Override",
                            definition: Text(
                                "Indicates when an override is or was active, temporarily changing therapy settings (e.g., basal rate, insulin sensitivity, carb ratio, target glucose, or whether Trio can dose SMBs)."
                            ),
                            color: Color.purple,
                            iconString: "button.horizontal.fill"
                        )

                        DefinitionRow(
                            term: "Temporary Target",
                            definition: Text(
                                "Marks when a short-term temporary glucose target is or was active, (potentially) altering when or how much insulin is delivered."
                            ),
                            color: Color.green.opacity(0.4),
                            iconString: "button.horizontal.fill"
                        )

                        DefinitionRow(
                            term: "Past Insulin-on-Board (IOB)",
                            definition: Text(
                                "Shows the IOB value calculated by the algorithm at a specific time in the past. These values are snapshots and won’t change if insulin is added or removed after the fact."
                            ),
                            color: Color.darkerBlue.opacity(0.8),
                            iconString: "line.diagonal"
                        )

                        DefinitionRow(
                            term: "Past Carbs-on-Board (COB)",
                            definition: Text(
                                "Shows the COB value calculated by the algorithm at a specific time in the past. These values are snapshots and won’t change if carbs are added or removed after the fact."
                            ),
                            color: Color.orange.opacity(0.8),
                            iconString: "line.diagonal"
                        )
                    }.listRowBackground(Color.gray.opacity(0.1))
                }
                .scrollContentBackground(.hidden)
                .navigationBarTitle("Chart Legend", displayMode: .inline)
                .padding(.trailing, 10)
                .padding(.bottom, 15)

                Button {
                    state.isLegendPresented.toggle()
                } label: {
                    Text("Got it!")
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .buttonStyle(.bordered)
                .padding(.top)
            }
            .padding([.horizontal, .bottom])
            .listSectionSpacing(10)
            .ignoresSafeArea(edges: .top)
            .presentationDetents(
                [.fraction(0.9), .large],
                selection: $legendSheetDetent
            )
        }
    }

    var legendLinesView: some View {
        Group {
            DefinitionRow(
                term: "IOB (Insulin on Board)",
                definition: Text(
                    "Forecasts future glucose readings based on the amount of insulin still active in the body."
                ),
                color: .insulin
            )

            DefinitionRow(
                term: "ZT (Zero-Temp)",
                definition: Text(
                    "Forecasts the worst-case future glucose reading scenario if no carbs are absorbed and insulin delivery is stopped until glucose starts rising."
                ),
                color: .zt
            )

            DefinitionRow(
                term: "COB (Carbs on Board)",
                definition: Text(
                    "Forecasts future glucose reading changes by considering the amount of carbohydrates still being absorbed in the body."
                ),
                color: .loopYellow
            )

            DefinitionRow(
                term: "UAM (Unannounced Meal)",
                definition: Text(
                    "Forecasts future glucose levels and insulin dosing needs for unexpected meals or other causes of glucose reading increases without prior notice."
                ),
                color: .uam
            )
        }
    }

    var legendConeOfUncertaintyView: some View {
        DefinitionRow(
            term: "Cone of Uncertainty",
            definition: VStack(alignment: .leading, spacing: 10) {
                Text(
                    "For simplicity reasons, oref's various forecast curves are displayed as a \"Cone of Uncertainty\" that depicts a possible, forecasted range of future glucose fluctuation based on the current data and the algothim's result."
                )
                Text(
                    "Note: To modify the forecast display type, go to Trio Settings > Features > User Interface > Forecast Display Type."
                )
            },
            color: Color.blue.opacity(0.5)
        )
    }
}
