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
                            term: String(localized: "Scheduled Basal Rate"),
                            definition: VStack(alignment: .leading, spacing: 10) {
                                Text("This dotted line represents the hourly insulin rate of your scheduled basal insulin.")
                                Text("To review or change your scheduled basal rates, go to Settings > Therapy > Basal Rates.")
                            },
                            color: Color.insulin,
                            iconString: "ellipsis"
                        )

                        DefinitionRow(
                            term: String(localized: "Temporary Basal Rate (TBR)"),
                            definition: Text(
                                "Shows current or past TBRs, which can be set by the oref algorithm or manually."
                            ),
                            color: Color.insulin,
                            iconString: "square"
                        )

                        DefinitionRow(
                            term: String(localized: "Pump Suspension"),
                            definition: Text("Indicates when insulin delivery was paused, i.e. pump is suspended."),
                            color: Color.loopGray.opacity(colorScheme == .dark ? 0.3 : 0.8),
                            iconString: "square.fill"
                        )

                        DefinitionRow(
                            term: String(localized: "CGM Glucose Value"),
                            definition: VStack(alignment: .leading, spacing: 10) {
                                if state.settingsManager.settings.smoothGlucose {
                                    Text(
                                        "Displays real-time glucose readings from your CGM that were smoothed using the Savatzky-Golay filter. The displayed glucose readings may not match the actual readings from your CGM."
                                    )
                                    Text(
                                        "Depending on your user interface settings, this may be displayed in a static (red, green, orange) or dynamic (full color spectrum) coloring scheme."
                                    )
                                } else {
                                    Text(
                                        "Displays real-time glucose readings from your CGM. Depending on your user interface settings, this may be displayed in a static (red, green, orange) or dynamic (full color spectrum) coloring scheme."
                                    )
                                }
                                Text(
                                    "To modify how glucose readings are displayed, go to Settings > Features > User Interface > Glucose Color Scheme."
                                )
                                if state.settingsManager.settings.smoothGlucose {
                                    Text(
                                        "To disable smoothing, go to Settings > Devices > Continuous Glucose Monitor > Smooth Glucose Value and toggle off the setting."
                                    )
                                }
                            },
                            color: Color.green,
                            iconString: state.settingsManager.settings.smoothGlucose ? "record.circle.fill" : "circle.fill"
                        )

                        DefinitionRow(
                            term: String(localized: "Manual Glucose Measurement"),
                            definition: Text("Manually entered blood glucose, such as a fingerstick test."),
                            color: Color.red,
                            iconString: "drop.fill"
                        )

                        DefinitionRow(
                            term: String(localized: "Bolus"),
                            definition: Text(
                                "Shows an insulin dose, which can be a small automated dose (super-micro-bolus), a manually entered dose, or one given externally (e.g., a pen shot)."
                            ),
                            color: Color.insulin,
                            iconString: "arrowtriangle.down.fill"
                        )

                        DefinitionRow(
                            term: String(localized: "Carb Entry"),
                            definition: Text("Tracks the carbohydrates you eat, entered to guide insulin dosing."),
                            color: Color.orange,
                            iconString: "arrowtriangle.down.fill",
                            shouldRotateIcon: true
                        )

                        DefinitionRow(
                            term: String(localized: "Fat-Protein Carb Equivalent"),
                            definition: VStack(alignment: .leading, spacing: 10) {
                                Text(
                                    "Represents carb equivalent for fat and protein, calculated using the Warsaw Method."
                                )
                                Text(
                                    "To enable or configure Warsaw Method application in Trio, go to Settings > Features > Meal Settings."
                                )
                            },
                            color: Color.brown,
                            iconString: "circle.fill"
                        )

                        DefinitionRow(
                            term: String(localized: "Override"),
                            definition: Text(
                                "Indicates when an override is or was active, temporarily changing therapy settings (e.g., basal rate, insulin sensitivity, carb ratio, target glucose, or whether Trio can dose SMBs)."
                            ),
                            color: Color.purple.opacity(0.4),
                            iconString: "button.horizontal.fill"
                        )

                        DefinitionRow(
                            term: String(localized: "Temporary Target"),
                            definition: Text(
                                "Marks when a short-term temporary glucose target is or was active, (potentially) altering when or how much insulin is delivered."
                            ),
                            color: Color.green.opacity(0.4),
                            iconString: "button.horizontal.fill"
                        )

                        DefinitionRow(
                            term: String(localized: "Past Insulin-on-Board (IOB)"),
                            definition: Text(
                                "Shows the IOB value calculated by the algorithm at a specific time in the past. These values are snapshots and won’t change if insulin is added or removed after the fact."
                            ),
                            color: Color.darkerBlue.opacity(0.8),
                            iconString: "line.diagonal"
                        )

                        DefinitionRow(
                            term: String(localized: "Past Carbs-on-Board (COB)"),
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
                selection: $legendSheetDetent
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
