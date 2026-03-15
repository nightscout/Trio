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
        @Environment(AppState.self) var appState

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
            List {
                Section(
                    header: Text("General Appearance"),
                    content: {
                        VStack {
                            Picker(
                                selection: $colorSchemePreference,
                                label: Text("Appearance")
                            ) {
                                ForEach(ColorSchemeOption.allCases) { selection in
                                    Text(selection.displayName).tag(selection)
                                }
                            }.padding(.top)

                            HStack(alignment: .center) {
                                Text(
                                    "Choose Trio's appearance. See hint for more details."
                                )
                                .font(.footnote)
                                .foregroundColor(.secondary)
                                .lineLimit(nil)
                                Spacer()
                                Button(
                                    action: {
                                        hintLabel = String(localized: "Color Scheme Preference")
                                        selectedVerboseHint =
                                            AnyView(
                                                VStack(alignment: .leading, spacing: 10) {
                                                    Text(
                                                        "Sets Trio's appearance. Descriptions of each option found below."
                                                    )
                                                    VStack(alignment: .leading, spacing: 5) {
                                                        Text("System Default:").bold()
                                                        Text("Follows the phone's current color scheme setting at that time")
                                                    }
                                                    VStack(alignment: .leading, spacing: 5) {
                                                        Text("Light:").bold()
                                                        Text("Always in Light mode")
                                                    }
                                                    VStack(alignment: .leading, spacing: 5) {
                                                        Text("Dark:").bold()
                                                        Text("Always in Dark mode")
                                                    }
                                                }
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

                        HStack(alignment: .center) {
                            Text(
                                "Choose glucose reading color scheme. See hint for more details."
                            )
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .lineLimit(nil)
                            Spacer()
                            Button(
                                action: {
                                    hintLabel = String(localized: "Glucose Color Scheme")
                                    selectedVerboseHint =
                                        AnyView(
                                            VStack(alignment: .leading, spacing: 10) {
                                                Text(
                                                    "Set the color scheme for glucose readings on the main glucose graph, live activities, and bolus calculator. Descriptions for each option found below."
                                                )
                                                VStack(alignment: .leading, spacing: 5) {
                                                    Text("Static:").bold()
                                                    Text("Red = Below Range")
                                                    Text("Green = In Range")
                                                    Text("Yellow = Above Range")
                                                }
                                                VStack(alignment: .leading, spacing: 5) {
                                                    Text("Dynamic:").bold()
                                                    Text("Green = At Target")
                                                    Text(
                                                        "Gradient Red = As readings approach and exceed below target, they gradually become more red."
                                                    )
                                                    Text(
                                                        "Gradient Purple = As readings approach and exceed above target, they become more purple."
                                                    )
                                                }
                                            }
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

                            HStack(alignment: .center) {
                                Text(
                                    "Display the grid lines behind the glucose graph."
                                )
                                .font(.footnote)
                                .foregroundColor(.secondary)
                                .lineLimit(nil)
                                Spacer()
                                Button(
                                    action: {
                                        hintLabel = String(localized: "Show Main Chart X- and Y-Axis Grid Lines")
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
                            hintLabel = String(localized: "Show Low and High Thresholds")
                        }
                    ),
                    units: state.units,
                    type: .boolean,
                    label: String(localized: "Show Low and High Thresholds"),
                    miniHint: String(localized: "Display the Low and High glucose thresholds set below."),
                    verboseHint: VStack(alignment: .leading, spacing: 10) {
                        Text("This setting displays the upper and lower values for your glucose target range.")
                        Text("This range is for display and statistical purposes only and does not influence insulin dosing.")
                    }
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

                            HStack(alignment: .center) {
                                Text(
                                    "Set low and high glucose values for the main screen, watch app and live activity glucose graph."
                                )
                                .lineLimit(nil)
                                .font(.footnote)
                                .foregroundColor(.secondary)

                                Spacer()
                                Button(
                                    action: {
                                        hintLabel = String(localized: "Low and High Thresholds")
                                        selectedVerboseHint =
                                            AnyView(
                                                VStack(alignment: .leading, spacing: 10) {
                                                    Text(
                                                        "Default values are based on internationally accepted Time in Range values of \(state.units == .mgdL ? "70" : 70.formattedAsMmolL)-\(state.units == .mgdL ? "180" : 180.formattedAsMmolL) \(state.units.rawValue)."
                                                    ).bold()
                                                    Text(
                                                        "Adjust these values if you would like the statistics to reflect different values than the internationally accepted Time In Range values used as the default."
                                                    )
                                                    Text("Note: These values are not used to calculate insulin dosing.")
                                                }
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

                        HStack(alignment: .center) {
                            Text(
                                "Choose glucose forecast presentation. See hint for more details."
                            )
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .lineLimit(nil)
                            Spacer()
                            Button(
                                action: {
                                    hintLabel = String(localized: "Forecast Display Type")
                                    selectedVerboseHint =
                                        AnyView(
                                            VStack(alignment: .leading, spacing: 10) {
                                                Text(
                                                    "This setting allows you to choose between Cone of Uncertainty (Cone) and OpenAPS Forecast Lines (Forecast Lines) for the glucose forecast. Descriptions for each option found below."
                                                )
                                                VStack(alignment: .leading, spacing: 5) {
                                                    Text("Cone:").bold()
                                                    Text(
                                                        "Uses a combined range of all possible forecasts from the OpenAPS lines and provides you with a range of possible forecasts. This option has shown to reduce confusion and stress around algorithm forecasts by providing a less concerning visual representation."
                                                    )
                                                }
                                                VStack(alignment: .leading, spacing: 5) {
                                                    Text("Forecast Lines:").bold()
                                                    Text(
                                                        "Uses the IOB, COB, UAM, and ZT forecast lines from OpenAPS. This option provides a more detailed view of the algorithm's forecast, but may be more confusing for some users."
                                                    )
                                                }
                                            }
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
                    header: Text("Trio Statistics"),
                    content: {
                        VStack {
                            Picker(
                                selection: $state.eA1cDisplayUnit,
                                label: Text("eA1c/GMI Display Unit")
                            ) {
                                ForEach(EstimatedA1cDisplayUnit.allCases) { selection in
                                    Text(selection.displayName).tag(selection)
                                }
                            }.padding(.top)

                            HStack(alignment: .center) {
                                Text(
                                    "Choose to display eA1c and GMI in percent or mmol/mol."
                                )
                                .font(.footnote)
                                .foregroundColor(.secondary)
                                .lineLimit(nil)
                                Spacer()
                                Button(
                                    action: {
                                        hintLabel = String(localized: "eA1c/GMI Display Unit")
                                        selectedVerboseHint =
                                            AnyView(
                                                Text(
                                                    "Choose which format you'd prefer the eA1c (estimated A1c) and GMI (Glucose Management Index) value in the statistics view as a percentage (Example: eA1c: 6.5%) or mmol/mol (Example: eA1c: 48 mmol/mol)."
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
                    VStack(alignment: .leading) {
                        Picker(
                            selection: $state.timeInRangeType,
                            label: Text("Time in Range Type").multilineTextAlignment(.leading)
                        ) {
                            ForEach(TimeInRangeType.allCases) { selection in
                                Text(selection.displayName).tag(selection)
                            }
                        }.padding(.top)

                        HStack(alignment: .center) {
                            Text(
                                "Choose type of time in range to be used for Trio's statistics."
                            )
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .lineLimit(nil)
                            Spacer()
                            Button(
                                action: {
                                    hintLabel = String(localized: "Time in Range Type")
                                    selectedVerboseHint =
                                        AnyView(
                                            VStack(
                                                alignment: .leading,
                                                spacing: 10
                                            ) {
                                                Text(
                                                    "Choose which type of time in range Trio should adopt for all its statistical charts and displays:"
                                                )
                                                VStack(
                                                    alignment: .leading,
                                                    spacing: 5
                                                ) {
                                                    Text(
                                                        "Time in Tight Range (TITR):"
                                                    )
                                                    .bold()
                                                    let titrBottomThreshold =
                                                        "\(state.units == .mgdL ? Decimal(70) : 70.asMmolL)"
                                                    let titrTopThreshold =
                                                        "\(state.units == .mgdL ? Decimal(140) : 140.asMmolL)"
                                                    Text(String(
                                                        localized: "Uses the fairly established Time in Tight Range definition, which is defined as time between \(titrBottomThreshold) and \(titrTopThreshold)  \(state.units.rawValue).",
                                                        comment: "Time in Tight Range (TITR) verbose hint description"
                                                    ))
                                                }
                                                VStack(
                                                    alignment: .leading,
                                                    spacing: 5
                                                ) {
                                                    Text(
                                                        "Time in Normoglycemia (TING):"
                                                    )
                                                    .bold()
                                                    let tingBottomThreshold =
                                                        "\(state.units == .mgdL ? Decimal(63) : 63.asMmolL)"
                                                    let tingTopThreshold =
                                                        "\(state.units == .mgdL ? Decimal(140) : 140.asMmolL)"
                                                    Text(String(
                                                        localized: "Uses the very new – first discussed at ATTD 2025 in Amsterdam, NL – Time in Normoglycemia definition, which adopts its range as all values between the normoglycemic minimum threshold (\(tingBottomThreshold) \(state.units.rawValue)) and \(tingTopThreshold) \(state.units.rawValue).",
                                                        comment: "Time in Normoglycemia (TING) verbose hint description"
                                                    ))
                                                }
                                            }
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
                    decimalValue: $state.carbsRequiredThreshold,
                    booleanValue: $state.showCarbsRequiredBadge,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = String(localized: "Show Carbs Required Badge")
                        }
                    ),
                    units: state.units,
                    type: .conditionalDecimal("carbsRequiredThreshold"),
                    label: String(localized: "Show Carbs Required Badge"),
                    conditionalLabel: String(localized: "Carbs Required Threshold"),
                    miniHint: String(localized: "Show carbs required as a red icon on the main graph icon."),
                    verboseHint: Text(
                        "Turning this on will show the grams of carbs needed to prevent a low as a notification badge on the Trio home screen located above the main icon.\n\nOnce enabled, set the Carbs Required Threshold to the lowest number of carbs you'd like to be recommended. A recommendation will not be given if carbs required is below this number.\n\nNote: The carbs suggested with this feature are to be used as a recommendation, not as a requirement. Depending on the current accuracy of your sensor and the accuracy of your settings, the suggested carbs can vary widely. Use your best judgement before injesting the suggested quanitity of carbs."
                    ),
                    headerText: String(localized: "Carbs Required Badge")
                )
            }
            .listSectionSpacing(sectionSpacing)
            .sheet(isPresented: $shouldDisplayHint) {
                SettingInputHintView(
                    hintDetent: $hintDetent,
                    shouldDisplayHint: $shouldDisplayHint,
                    hintLabel: hintLabel ?? "",
                    hintText: selectedVerboseHint ?? AnyView(EmptyView()),
                    sheetTitle: String(localized: "Help", comment: "Help sheet title")
                )
            }
            .scrollContentBackground(.hidden)
            .background(appState.trioBackgroundColor(for: colorScheme))
            .onAppear(perform: configureView)
            .navigationBarTitle("User Interface")
            .navigationBarTitleDisplayMode(.automatic)
        }
    }
}
