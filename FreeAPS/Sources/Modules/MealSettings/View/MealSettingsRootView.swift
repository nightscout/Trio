import SwiftUI
import Swinject

extension MealSettings {
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

        private var conversionFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 1

            return formatter
        }

        private var intFormater: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.allowsFloats = false
            return formatter
        }

        private var formatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            return formatter
        }

        var body: some View {
            Form {
                Section(
                    header: Text("Limits per Entry"),
                    content: {
                        VStack {
                            HStack {
                                Text("Max Carbs")
                                TextFieldWithToolBar(text: $state.maxCarbs, placeholder: "g", numberFormatter: formatter)
                            }.padding(state.useFPUconversion ? .top : .vertical)

                            if state.useFPUconversion {
                                HStack {
                                    Text("Max Fat")
                                    TextFieldWithToolBar(text: $state.maxFat, placeholder: "g", numberFormatter: formatter)
                                }
                                HStack {
                                    Text("Max Protein")
                                    TextFieldWithToolBar(text: $state.maxProtein, placeholder: "g", numberFormatter: formatter)
                                }.padding(.bottom)
                            }

                            HStack(alignment: .top) {
                                Text(
                                    "Set limits for entering meals in treatment view."
                                )
                                .lineLimit(nil)
                                .font(.footnote)
                                .foregroundColor(.secondary)

                                Spacer()
                                Button(
                                    action: {
                                        hintLabel = "Limits per Entry"
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
                    }
                ).listRowBackground(Color.chart)

                SettingInputSection(
                    decimalValue: $decimalPlaceholder,
                    booleanValue: $state.useFPUconversion,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0
                            hintLabel = "Display and Allow Fat and Protein Entries"
                        }
                    ),
                    type: .boolean,
                    label: "Display and Allow Fat and Protein Entries",
                    miniHint: "Lorem ipsum dolor sit amet, consetetur sadipscing elitr.",
                    verboseHint: "Allows fat and protein to be converted into future carb equivalents using the Warsaw formula of kilocalories divided by 10.\n\nDefaults: Spread Duration: 8 h, Spread Interval: 30 min, FPU Factor: 0.5, Delay 60 min.",
                    headerText: "Fat and Protein"
                )

                if state.useFPUconversion {
                    SettingInputSection(
                        decimalValue: $state.delay,
                        booleanValue: $booleanPlaceholder,
                        shouldDisplayHint: $shouldDisplayHint,
                        selectedVerboseHint: Binding(
                            get: { selectedVerboseHint },
                            set: {
                                selectedVerboseHint = $0
                                hintLabel = "Fat and Protein Delay"
                            }
                        ),
                        type: .decimal,
                        label: "Fat and Protein Delay",
                        miniHint: "Delay is time from now until the first future carb entry.",
                        verboseHint: "X-Axis Interval Step… bla bla bla"
                    )

                    SettingInputSection(
                        decimalValue: $state.timeCap,
                        booleanValue: $booleanPlaceholder,
                        shouldDisplayHint: $shouldDisplayHint,
                        selectedVerboseHint: Binding(
                            get: { selectedVerboseHint },
                            set: {
                                selectedVerboseHint = $0
                                hintLabel = "Maximum Duration (hours)"
                            }
                        ),
                        type: .decimal,
                        label: "Maximum Duration (hours)",
                        miniHint: "Carb spread over a maximum number of hours (5-12).",
                        verboseHint: "This spreads the carb equivilants over a maximum duration setting that can be configured from 5-12 hours."
                    )

                    SettingInputSection(
                        decimalValue: $state.minuteInterval,
                        booleanValue: $booleanPlaceholder,
                        shouldDisplayHint: $shouldDisplayHint,
                        selectedVerboseHint: Binding(
                            get: { selectedVerboseHint },
                            set: {
                                selectedVerboseHint = $0
                                hintLabel = "Spread Interval (minutes)"
                            }
                        ),
                        type: .decimal,
                        label: "Spread Interval (minutes)",
                        miniHint: "Interval in minutes is how many minutes are between entries.",
                        verboseHint: "Interval in minutes is how many minutes are between entries. The shorter the interval, the smoother the result. 10, 15, 20, 30, or 60 are reasonable choices."
                    )

                    SettingInputSection(
                        decimalValue: $state.minuteInterval,
                        booleanValue: $booleanPlaceholder,
                        shouldDisplayHint: $shouldDisplayHint,
                        selectedVerboseHint: Binding(
                            get: { selectedVerboseHint },
                            set: {
                                selectedVerboseHint = $0
                                hintLabel = "Fat and Protein Factor"
                            }
                        ),
                        type: .decimal,
                        label: "Fat and Protein Factor",
                        miniHint: "Influences how many carb equivalents are recorded for fat and protein.",
                        verboseHint: "The Fat and Protein Factor influences how much effect the fat and protein has on the entries. 1.0 is full effect (original Warsaw Method) and 0.5 is half effect. Note that you may find that your normal carb ratio needs to increase to a larger number if you begin adding fat and protein entries. For this reason, it is best to start with a factor of about 0.5 to ease into it."
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
            .navigationBarTitle("Meal Settings")
            .navigationBarTitleDisplayMode(.automatic)
        }
    }
}
