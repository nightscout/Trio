import SwiftUI
import Swinject

extension AutosensSettings {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()
        @State private var shouldDisplayHint: Bool = false
        @State var hintDetent = PresentationDetent.large
        @State var selectedVerboseHint: AnyView?
        @State var hintLabel: String?
        @State private var decimalPlaceholder: Decimal = 0.0
        @State private var booleanPlaceholder: Bool = false

        @Environment(\.colorScheme) var colorScheme
        @EnvironmentObject var appIcons: Icons
        @Environment(AppState.self) var appState

        private var rateFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 2
            return formatter
        }

        var autosensVerboseHint: some View {
            VStack(alignment: .leading, spacing: 15) {
                Text(
                    "Autosens automatically adjusts insulin delivery based on how sensitive or resistant you are to insulin at the time of the current loop cycle by analyzing past data to keep blood sugar levels stable."
                )

                VStack(alignment: .leading, spacing: 5) {
                    Text("How it Works").bold()
                    Text(
                        "It looks at the last 8-24 hours of data, excluding meal-related changes, and adjusts insulin settings like basal rates and targets when needed to match your sensitivity or resistance to insulin."
                    )
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text("What it Adjusts").bold()
                    Text(
                        "Autosens modifies Insulin Sensitivity Factor (ISF), basal rates, and target glucose. It doesn’t account for carbs but adjusts for insulin effectiveness based on patterns in your glucose data."
                    )
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text("Safety").bold()
                    Text(
                        "Autosens has safety limits determined by your Autosens Max and Autosens Min settings. These settings prevent over-adjusting."
                    )
                }

                Text(
                    "Autosens functions alongside certain settings, like Super Micro Bolus (SMB). Other settings, like Dynamic ISF, alter portions of the Autosens formula. Please review the in-app hints for the Algorithm Settings prior to enabling them to understand how they may influence it."
                )
            }
        }

        var AutosensView: some View {
            Section(
                header: !state.settingsManager.preferences
                    .useNewFormula ? Text("Autosens") : Text("Dynamic Sensitivity")
            ) {
                VStack {
                    let dynamicRatio = state.determinationsFromPersistence.first?.sensitivityRatio
                    let dynamicISF = state.determinationsFromPersistence.first?.insulinSensitivity
                    let newISF = state.autosensISF
                    let decimalValue = !state.settingsManager.preferences.useNewFormula ? state
                        .autosensRatio as NSDecimalNumber : dynamicRatio ?? 1
                    let decimalValueText = rateFormatter
                        .string(from: ((decimalValue as Decimal) * Decimal(100)) as NSNumber) ?? "100"

                    HStack {
                        Text("Sensitivity Ratio")
                        Spacer()
                        Text("\(decimalValueText) \(String(localized: "%", comment: "Percentage symbol"))")
                    }.padding(.vertical)
                    HStack {
                        Text("Calculated Sensitivity")
                        Spacer()
                        if state.units == .mgdL {
                            Text(
                                !state.settingsManager.preferences
                                    .useNewFormula ? newISF!.description : (dynamicISF ?? 0).description
                            )
                        } else {
                            Text((
                                !state.settingsManager.preferences
                                    .useNewFormula ? newISF!.formattedAsMmolL : dynamicISF?.decimalValue.formattedAsMmolL
                            ) ?? "0")
                        }
                        Text(state.units.rawValue + "/U").foregroundColor(.secondary)
                    }

                    HStack(alignment: .top) {
                        Text(
                            "This adjusted ISF is temporary, will change with the next loop cycle, and should not be directly used as your profile ISF value."
                        )
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .lineLimit(nil)
                        Spacer()
                        Button(
                            action: {
                                hintLabel = String(localized: "Autosens")
                                selectedVerboseHint = AnyView(autosensVerboseHint)
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

        var body: some View {
            List {
                if state.autosensISF != nil {
                    AutosensView
                }

                SettingInputSection(
                    decimalValue: $state.autosensMax,
                    booleanValue: $booleanPlaceholder,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = String(localized: "Autosens Max", comment: "Autosens Max")
                        }
                    ),
                    units: state.units,
                    type: .decimal("autosensMax"),
                    label: String(localized: "Autosens Max", comment: "Autosens Max"),
                    miniHint: String(localized: "Upper limit of the Sensitivity Ratio."),
                    verboseHint:
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Default: 120%").bold()
                        Text(
                            "Autosens Max sets the maximum Sensitivity Ratio used by Autosens, Dynamic ISF, and Sigmoid Formula."
                        )
                        Text(
                            "The Sensitivity Ratio is used to calculate the amount of adjustment needed to basal rates and ISF."
                        )
                        Text(
                            "Tip: Increasing this value allows automatic adjustments of basal rates to be higher and ISF to be lower."
                        )
                    },
                    headerText: String(localized: "Glucose Deviations Algorithm")
                )

                SettingInputSection(
                    decimalValue: $state.autosensMin,
                    booleanValue: $booleanPlaceholder,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = String(localized: "Autosens Min", comment: "Autosens Min")
                        }
                    ),
                    units: state.units,
                    type: .decimal("autosensMin"),
                    label: String(localized: "Autosens Min", comment: "Autosens Min"),
                    miniHint: String(localized: "Lower limit of the Sensitivity Ratio."),
                    verboseHint:
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Default: 70%").bold()
                        Text(
                            "Autosens Min sets the minimum Sensitivity Ratio used by Autosens, Dynamic ISF, and Sigmoid Formula."
                        )
                        Text(
                            "The Sensitivity Ratio is used to calculate the amount of adjustment needed to basal rates and ISF."
                        )
                        Text(
                            "Tip: Decreasing this value allows automatic adjustments of basal rates to be lower and ISF to be higher."
                        )
                    }
                )

                SettingInputSection(
                    decimalValue: $decimalPlaceholder,
                    booleanValue: $state.rewindResetsAutosens,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = String(localized: "Rewind Resets Autosens", comment: "Rewind Resets Autosens")
                        }
                    ),
                    units: state.units,
                    type: .boolean,
                    label: String(localized: "Rewind Resets Autosens", comment: "Rewind Resets Autosens"),
                    miniHint: String(localized: "Pump rewind initiates a reset in Sensitivity Ratio."),
                    verboseHint: VStack(alignment: .leading, spacing: 5) {
                        Text("Default: ON").bold()
                        Text("Medtronic and Dana Users Only").bold()
                        VStack(alignment: .leading, spacing: 10) {
                            Text(
                                "This feature resets the Sensitivity Ratio to neutral when you rewind your pump on the assumption that this corresponds to a site change."
                            )
                            Text(
                                "Autosens will begin learning sensitivity anew from the time of the rewind, which may take up to 6 hours."
                            )
                            Text(
                                "Tip: If you usually rewind your pump independently of site changes, you may want to consider disabling this feature."
                            )
                        }
                    }
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
            .scrollContentBackground(.hidden).background(appState.trioBackgroundColor(for: colorScheme))
            .onAppear(perform: configureView)
            .navigationTitle("Autosens")
            .navigationBarTitleDisplayMode(.automatic)
        }
    }
}
