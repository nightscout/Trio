import SwiftUI
import Swinject

extension UserInterfaceSettings {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()

        @State private var shouldDisplayHint: Bool = false
        @State var hintDetent = PresentationDetent.large
        @State var selectedVerboseHint: AnyView?
        @State var hintLabel: String?
        @State private var decimalPlaceholder: Decimal = 0.0
        @State private var booleanPlaceholder: Bool = false
        @State private var displayPickerLowThreshold: Bool = false
        @State private var displayPickerHighThreshold: Bool = false

        @AppStorage("colorSchemePreference") private var colorSchemePreference: ColorSchemeOption = .systemDefault

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

        private var glucoseFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 0
            if state.units == .mmolL {
                formatter.maximumFractionDigits = 1
            }
            formatter.roundingMode = .halfUp
            return formatter
        }

        private var carbsFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 0
            return formatter
        }

        var body: some View {
            Form {
                Section(
                    header: Text("General Appearance"),
                    content: {
                        VStack {
                            Picker(
                                selection: $colorSchemePreference,
                                label: Text("Trio Color Scheme")
                            ) {
                                ForEach(ColorSchemeOption.allCases) { selection in
                                    Text(selection.displayName).tag(selection)
                                }
                            }.padding(.top)

                            HStack(alignment: .top) {
                                Text(
                                    "Choose between Light, Dark, or System Default for the app color scheme"
                                )
                                .font(.footnote)
                                .foregroundColor(.secondary)
                                .lineLimit(nil)
                                Spacer()
                                Button(
                                    action: {
                                        hintLabel = "Color Scheme Preference"
                                        selectedVerboseHint =
                                            AnyView(
                                                Text(
                                                    "Set the app color scheme using the following options \n\nSystem Default: Follows the phone's current color scheme setting at that time\nLight: Always in Light mode \nDark: Always in Dark mode"
                                                )
                                            )
                                        shouldDisplayHint.toggle()
                                    },
                                    label: {
                                        HStack {
                                            Image(systemName: "questionmark.circle")
                                        }
                                    }
                                ).buttonStyle(BorderlessButtonStyle())
                            }.padding(.top)
                        }.padding(.bottom)
                    }
                ).listRowBackground(Color.chart)

                Section {
                    VStack {
                        Picker(
                            selection: $state.glucoseColorScheme,
                            label: Text("Glucose Color Scheme")
                        ) {
                            ForEach(GlucoseColorScheme.allCases) { selection in
                                Text(selection.displayName).tag(selection)
                            }
                        }.padding(.top)

                        HStack(alignment: .top) {
                            Text(
                                "Choose between Static or Dynamic coloring for glucose readings"
                            )
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .lineLimit(nil)
                            Spacer()
                            Button(
                                action: {
                                    hintLabel = "Glucose Color Scheme"
                                    selectedVerboseHint =
                                        AnyView(
                                            Text(
                                                "Set the color scheme for glucose readings on the main glucose graph, live activities, and bolus calculator using the following options: \n\nStatic: Below-Range Target readings will be in RED, In-Range will be GREEN, Above-Range will be YELLOW \n\nDynamic: Readings on Target will be GREEN. As readings approach and exceed below target, they become more RED. As readings approach and exceed above targer, they become more PURPLE."
                                            )
                                        )
                                    shouldDisplayHint.toggle()
                                },
                                label: {
                                    HStack {
                                        Image(systemName: "questionmark.circle")
                                    }
                                }
                            ).buttonStyle(BorderlessButtonStyle())
                        }.padding(.top)
                    }.padding(.bottom)
                }.listRowBackground(Color.chart)

                Section(
                    header: Text("Home View Settings"),
                    content: {
                        VStack {
                            Toggle("Show X-Axis Grid Lines", isOn: $state.xGridLines)
                            Toggle("Show Y-Axis Grid Lines", isOn: $state.yGridLines)

                            HStack(alignment: .top) {
                                Text(
                                    "Display the grid lines behind the glucose graph"
                                )
                                .font(.footnote)
                                .foregroundColor(.secondary)
                                .lineLimit(nil)
                                Spacer()
                                Button(
                                    action: {
                                        hintLabel = "Show Main Chart X- and Y-Axis Grid Lines"
                                        selectedVerboseHint =
                                            AnyView(
                                                Text("Choose whether or not to display one or both X- and Y-Axis grid lines.")
                                            )
                                        shouldDisplayHint.toggle()
                                    },
                                    label: {
                                        HStack {
                                            Image(systemName: "questionmark.circle")
                                        }
                                    }
                                ).buttonStyle(BorderlessButtonStyle())
                            }.padding(.top)
                        }.padding(.vertical)
                    }
                ).listRowBackground(Color.chart)

                SettingInputSection(
                    decimalValue: $decimalPlaceholder,
                    booleanValue: $state.rulerMarks,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = "Show Low and High Thresholds"
                        }
                    ),
                    units: state.units,
                    type: .boolean,
                    label: "Show Low and High Thresholds",
                    miniHint: "Display the Low and High glucose thresholds set below",
                    verboseHint: Text(
                        "This setting displays the upper and lower values for your glucose target range. \n\nThis range is for display and statistical purposes only and does not influence insulin dosing."
                    )
                )

                if state.rulerMarks {
                    Section {
                        VStack {
                            VStack {
                                HStack {
                                    Text("Low Threshold")

                                    Spacer()

                                    Group {
                                        Text(state.units == .mgdL ? state.low.description : state.low.asMmolL.description)
                                            .foregroundColor(!displayPickerLowThreshold ? .primary : .accentColor)

                                        Text(state.units == .mgdL ? " mg/dL" : " mmol/L").foregroundColor(.secondary)
                                    }
                                }
                                .onTapGesture {
                                    displayPickerLowThreshold.toggle()
                                }
                            }
                            .padding(.top)

                            if displayPickerLowThreshold {
                                let setting = PickerSettingsProvider.shared.settings.low

                                Picker(selection: $state.low, label: Text("")) {
                                    ForEach(
                                        PickerSettingsProvider.shared.generatePickerValues(from: setting, units: state.units),
                                        id: \.self
                                    ) { value in
                                        let displayValue = state.units == .mgdL ? value : value.asMmolL
                                        Text("\(displayValue.description)").tag(value)
                                    }
                                }
                                .pickerStyle(WheelPickerStyle())
                                .frame(maxWidth: .infinity)
                            }

                            VStack {
                                HStack {
                                    Text("High Threshold")

                                    Spacer()

                                    Group {
                                        Text(state.units == .mgdL ? state.high.description : state.high.asMmolL.description)
                                            .foregroundColor(!displayPickerHighThreshold ? .primary : .accentColor)

                                        Text(state.units == .mgdL ? " mg/dL" : " mmol/L").foregroundColor(.secondary)
                                    }
                                }
                                .onTapGesture {
                                    displayPickerHighThreshold.toggle()
                                }
                            }
                            .padding(.top)

                            if displayPickerHighThreshold {
                                let setting = PickerSettingsProvider.shared.settings.high
                                Picker(selection: $state.high, label: Text("")) {
                                    ForEach(
                                        PickerSettingsProvider.shared.generatePickerValues(from: setting, units: state.units),
                                        id: \.self
                                    ) { value in
                                        let displayValue = state.units == .mgdL ? value : value.asMmolL
                                        Text("\(displayValue.description)").tag(value)
                                    }
                                }
                                .pickerStyle(WheelPickerStyle())
                                .frame(maxWidth: .infinity)
                            }

                            HStack(alignment: .top) {
                                Text(
                                    "Set low and high glucose values for the main screen glucose graph and statistics \nLow Default: 70 \nHigh Default: 180"
                                )
                                .lineLimit(nil)
                                .font(.footnote)
                                .foregroundColor(.secondary)

                                Spacer()
                                Button(
                                    action: {
                                        hintLabel = "Low and High Thresholds"
                                        selectedVerboseHint =
                                            AnyView(
                                                Text(
                                                    "Default values are based on internationally accepted Time in Range values of 70-180 mg/dL (5.5-10 mmol/L) \nSet the values used in the main screen glucose graph and to determine Time in Range for Statistics. \nNote: These values are not used to calculate insulin dosing."
                                                )
                                            )

                                        shouldDisplayHint.toggle()
                                    },
                                    label: {
                                        HStack {
                                            Image(systemName: "questionmark.circle")
                                        }
                                    }
                                ).buttonStyle(BorderlessButtonStyle())
                            }.padding(.top)
                        }.padding(.bottom)
                    }.listRowBackground(Color.chart)
                }

                Section {
                    VStack {
                        Picker(
                            selection: $state.forecastDisplayType,
                            label: Text("Forecast Display Type")
                        ) {
                            ForEach(ForecastDisplayType.allCases) { selection in
                                Text(selection.displayName).tag(selection)
                            }
                        }.padding(.top)

                        HStack(alignment: .top) {
                            Text(
                                "Choose between the OpenAPS colored Lines or the Cone of Uncertainty for the Forecast Lines"
                            )
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .lineLimit(nil)
                            Spacer()
                            Button(
                                action: {
                                    hintLabel = "Forecast Display Type"
                                    selectedVerboseHint =
                                        AnyView(
                                            Text(
                                                "This setting allows you to choose between the following two options for the Forecast lines (previously: Prediction Lines). \n\nLines: Uses the IOB, COB, UAM, and ZT forecast lines from OpenAPS \n\nCone: Uses a combined range of all possible forecasts from the OpenAPS lines and provides you with a range of possible forecasts. This option has shown to reduce confusion and stress around algorithm forecasts by providing a less concerning visual representation."
                                            )
                                        )
                                    shouldDisplayHint.toggle()
                                },
                                label: {
                                    HStack {
                                        Image(systemName: "questionmark.circle")
                                    }
                                }
                            ).buttonStyle(BorderlessButtonStyle())
                        }.padding(.top)
                    }.padding(.bottom)
                }.listRowBackground(Color.chart)

                SettingInputSection(
                    decimalValue: $state.hours,
                    booleanValue: $booleanPlaceholder,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = "X-Axis Interval Step"
                        }
                    ),
                    units: state.units,
                    type: .decimal("hours"),
                    label: "X-Axis Interval Step",
                    miniHint: "Determines how many hours are shown in the main graph",
                    verboseHint: Text(
                        "Default: 6 hours \n\nThis setting determines how many hours are shown in the primary view of the main graph."
                    )
                )

                Section {
                    VStack {
                        Picker(
                            selection: $state.totalInsulinDisplayType,
                            label: Text("Total Insulin Display Type")
                        ) {
                            ForEach(TotalInsulinDisplayType.allCases) { selection in
                                Text(selection.displayName).tag(selection)
                            }
                        }.padding(.top)

                        HStack(alignment: .top) {
                            Text(
                                "Choose between Total Daily Dose (TDD) or Total Insulin in Scope (TINS) to be displayed above the main glucose graph"
                            )
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .lineLimit(nil)
                            Spacer()
                            Button(
                                action: {
                                    hintLabel = "Total Insulin Display Type"
                                    selectedVerboseHint =
                                        AnyView(
                                            Text(
                                                "Choose between Total Daily Dose (TDD) or Total Insulin in Scope (TINS) to be displayed above the main glucose graph.\n\nTotal Daily Dose: Displays the last 24 hours of total insulin administered, both basal and bolus. \n\nTotal Insulin in Scope: Displays the total insulin administered since midnight, both basal and bolus."
                                            )
                                        )
                                    shouldDisplayHint.toggle()
                                },
                                label: {
                                    HStack {
                                        Image(systemName: "questionmark.circle")
                                    }
                                }
                            ).buttonStyle(BorderlessButtonStyle())
                        }.padding(.top)
                    }.padding(.bottom)
                }.listRowBackground(Color.chart)

                // TODO: this needs to be a picker: mmol/L or %
                SettingInputSection(
                    decimalValue: $decimalPlaceholder,
                    booleanValue: $state.overrideHbA1cUnit,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = "Override HbA1c Unit"
                        }
                    ),
                    units: state.units,
                    type: .boolean,
                    label: "Override HbA1c Unit",
                    miniHint: "Display HbA1c in mmol/mol or %",
                    verboseHint: Text(
                        "Choose which format you'd prefer the HbA1c value in the statistics view as a percentage (Example: 6.5%) or mmol/mol (Example: 48 mmol/mol)"
                    ),
                    headerText: "Trio Statistics"
                )

                // TODO: this needs to be a picker: choose bar chart or progress bar
                SettingInputSection(
                    decimalValue: $decimalPlaceholder,
                    booleanValue: $state.oneDimensionalGraph,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = "Standing / Laying TIR Chart"
                        }
                    ),
                    units: state.units,
                    type: .boolean,
                    label: "Standing / Laying TIR Chart",
                    miniHint: "Select a vertical chart or horizontal chart to display your Time in Range Statistics",
                    verboseHint: Text(
                        "Select a vertical / standing chart by turning this feature OFF \n\nSelect a horizontal / laying chart by turning this feature ON"
                    )
                )

                SettingInputSection(
                    decimalValue: $state.carbsRequiredThreshold,
                    booleanValue: $state.showCarbsRequiredBadge,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = "Show Carbs Required Badge"
                        }
                    ),
                    units: state.units,
                    type: .conditionalDecimal("carbsRequiredThreshold"),
                    label: "Show Carbs Required Badge",
                    conditionalLabel: "Carbs Required Threshold",
                    miniHint: "Show carbs required as a notification badge on the home screen",
                    verboseHint: Text(
                        "Turning this on will show the grams of carbs needed to prevent a low as a notification badge on the Trio home screen located above the main icon"
                    ),
                    headerText: "Carbs Required Badge"
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
            .navigationBarTitle("User Interface")
            .navigationBarTitleDisplayMode(.automatic)
        }
    }
}
