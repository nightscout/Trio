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
                    header: Text("Home View Settings"),
                    content: {
                        VStack {
                            Toggle("Show X-Axis Grid Lines", isOn: $state.xGridLines)
                            Toggle("Show Y-Axis Grid Line", isOn: $state.yGridLines)

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
                        }.padding(.bottom)
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
                    type: .boolean,
                    label: "Show Low and High Thresholds",
                    miniHint: "Lorem ipsum dolor sit amet, consetetur sadipscing elitr.",
                    verboseHint: "Display Low and High Thresholds… bla bla bla"
                )

                Section {
                    VStack {
                        HStack {
                            Text("Low Threshold")
                            Spacer()
                            TextFieldWithToolBar(text: $state.low, placeholder: "0", numberFormatter: glucoseFormatter)
                            Text(state.units.rawValue).foregroundColor(.secondary)
                        }.padding(.top)
                        HStack {
                            Text("High Threshold")
                            Spacer()
                            TextFieldWithToolBar(text: $state.high, placeholder: "0", numberFormatter: glucoseFormatter)
                            Text(state.units.rawValue).foregroundColor(.secondary)
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
                        }
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
                    type: .decimal,
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
                    type: .boolean,
                    label: "Standing / Laying TIR Chart",
                    miniHint: "Lorem ipsum dolor sit amet, consetetur sadipscing elitr.",
                    verboseHint: "Standing / Laying TIR Chart… bla bla bla"
                )

                SettingInputSection(
                    decimalValue: $decimalPlaceholder,
                    booleanValue: $state.showCarbsRequiredBadge,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0
                            hintLabel = "Show Carbs Required Badge"
                        }
                    ),
                    type: .boolean,
                    label: "Show Carbs Required Badge",
                    miniHint: "Lorem ipsum dolor sit amet, consetetur sadipscing elitr.",
                    verboseHint: "Show Carbs Required Badge… bla bla bla",
                    headerText: "Carbs Required Badge"
                )

                if state.showCarbsRequiredBadge {
                    SettingInputSection(
                        decimalValue: $state.carbsRequiredThreshold,
                        booleanValue: $booleanPlaceholder,
                        shouldDisplayHint: $shouldDisplayHint,
                        selectedVerboseHint: Binding(
                            get: { selectedVerboseHint },
                            set: {
                                selectedVerboseHint = $0
                                hintLabel = "Carbs Required Threshold"
                            }
                        ),
                        type: .decimal,
                        label: "Carbs Required Threshold",
                        miniHint: "Lorem ipsum dolor sit amet, consetetur sadipscing elitr.",
                        verboseHint: "Carbs Required Threshold… bla bla bla"
                    )
                }
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
