import SwiftUI
import Swinject

extension UserInterfaceSettings {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()

        @State private var shouldDisplayHint: Bool = false
        @State var hintDetent = PresentationDetent.large
        @State var selectedVerboseHint: String?
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
                                label: Text("Color Scheme")
                            ) {
                                ForEach(ColorSchemeOption.allCases) { selection in
                                    Text(selection.displayName).tag(selection)
                                }
                            }.padding(.top)

                            HStack(alignment: .top) {
                                Text(
                                    "Lorem ipsum dolor sit amet, consetetur sadipscing elitr."
                                )
                                .font(.footnote)
                                .foregroundColor(.secondary)
                                .lineLimit(nil)
                                Spacer()
                                Button(
                                    action: {
                                        hintLabel = "Color Scheme Preference"
                                        selectedVerboseHint = "Lorem ipsum dolor sit amet, consetetur sadipscing elitr."
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
                                "Glucose Scheme Preference ... dynamic or static ... Lorem ipsum dolor"
                            )
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .lineLimit(nil)
                            Spacer()
                            Button(
                                action: {
                                    hintLabel = "Glucose Scheme Preference"
                                    selectedVerboseHint =
                                        "Glucose Scheme Preference... Lorem ipsum dolor sit amet, consetetur sadipscing elitr."
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
                                    "Lorem ipsum dolor sit amet, consetetur sadipscing elitr."
                                )
                                .font(.footnote)
                                .foregroundColor(.secondary)
                                .lineLimit(nil)
                                Spacer()
                                Button(
                                    action: {
                                        hintLabel = "Show Main Chart X- and Y-Axis Grid Lines"
                                        selectedVerboseHint = "Lorem ipsum dolor sit amet, consetetur sadipscing elitr."
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
                            selectedVerboseHint = $0
                            hintLabel = "Show Low and High Thresholds"
                        }
                    ),
                    units: state.units,
                    type: .boolean,
                    label: "Show Low and High Thresholds",
                    miniHint: "Lorem ipsum dolor sit amet, consetetur sadipscing elitr.",
                    verboseHint: "Display Low and High Thresholds… bla bla bla"
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
                                    "Sets thresholds for low and high glucose in home view main chart and statistics view."
                                )
                                .lineLimit(nil)
                                .font(.footnote)
                                .foregroundColor(.secondary)

                                Spacer()
                                Button(
                                    action: {
                                        hintLabel = "Low and High Thresholds"
                                        selectedVerboseHint = "Lorem ipsum dolor sit amet, consetetur sadipscing elitr."
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
                                "Lorem ipsum dolor sit amet, consetetur sadipscing elitr."
                            )
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .lineLimit(nil)
                            Spacer()
                            Button(
                                action: {
                                    hintLabel = "Forecast Display Type"
                                    selectedVerboseHint = "Lorem ipsum dolor sit amet, consetetur sadipscing elitr."
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
                            selectedVerboseHint = $0
                            hintLabel = "X-Axis Interval Step"
                        }
                    ),
                    units: state.units,
                    type: .decimal("hours"),
                    label: "X-Axis Interval Step",
                    miniHint: "Lorem ipsum dolor sit amet, consetetur sadipscing elitr.",
                    verboseHint: "X-Axis Interval Step… bla bla bla"
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
                                "Lorem ipsum dolor sit amet, consetetur sadipscing elitr."
                            )
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .lineLimit(nil)
                            Spacer()
                            Button(
                                action: {
                                    hintLabel = "Total Insulin Display Type"
                                    selectedVerboseHint = "Lorem ipsum dolor sit amet, consetetur sadipscing elitr."
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
                            selectedVerboseHint = $0
                            hintLabel = "Override HbA1c Unit"
                        }
                    ),
                    units: state.units,
                    type: .boolean,
                    label: "Override HbA1c Unit",
                    miniHint: "Display HbA1c in mmol/L or %. Default is percent.",
                    verboseHint: "Override HbA1c Unit… bla bla bla",
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
                            selectedVerboseHint = $0
                            hintLabel = "Standing / Laying TIR Chart"
                        }
                    ),
                    units: state.units,
                    type: .boolean,
                    label: "Standing / Laying TIR Chart",
                    miniHint: "Lorem ipsum dolor sit amet, consetetur sadipscing elitr.",
                    verboseHint: "Standing / Laying TIR Chart… bla bla bla"
                )

                SettingInputSection(
                    decimalValue: $state.carbsRequiredThreshold,
                    booleanValue: $state.showCarbsRequiredBadge,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0
                            hintLabel = "Show Carbs Required Badge"
                        }
                    ),
                    units: state.units,
                    type: .conditionalDecimal("carbsRequiredThreshold"),
                    label: "Show Carbs Required Badge",
                    conditionalLabel: "Carbs Required Threshold",
                    miniHint: "Lorem ipsum dolor sit amet, consetetur sadipscing elitr.",
                    verboseHint: "Show Carbs Required Badge… bla bla bla",
                    headerText: "Carbs Required Badge"
                )
            }
            .sheet(isPresented: $shouldDisplayHint) {
                SettingInputHintView(
                    hintDetent: $hintDetent,
                    shouldDisplayHint: $shouldDisplayHint,
                    hintLabel: hintLabel ?? "",
                    hintText: selectedVerboseHint ?? "",
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
