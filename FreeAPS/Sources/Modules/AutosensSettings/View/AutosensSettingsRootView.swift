import SwiftUI
import Swinject

extension AutosensSettings {
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
        @EnvironmentObject var appIcons: Icons
        @Environment(AppState.self) var appState

        private var rateFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 2
            return formatter
        }

        var body: some View {
            List {
                if let newISF = state.autosensISF {
                    Section(
                        header: !state.settingsManager.preferences
                            .useNewFormula ? Text("Autosens") : Text("Dynamic Sensitivity")
                    ) {
                        VStack {
                            let dynamicRatio = state.determinationsFromPersistence.first?.sensitivityRatio
                            let dynamicISF = state.determinationsFromPersistence.first?.insulinSensitivity
                            HStack {
                                Text("Sensitivity Ratio")
                                Spacer()
                                Text(
                                    rateFormatter
                                        .string(from: (
                                            (
                                                !state.settingsManager.preferences.useNewFormula ? state
                                                    .autosensRatio as NSDecimalNumber : dynamicRatio
                                            ) ?? 1
                                        ) as NSNumber) ?? "1"
                                )
                            }.padding(.vertical)
                            HStack {
                                Text("Calculated Sensitivity")
                                Spacer()
                                if state.units == .mgdL {
                                    Text(
                                        !state.settingsManager.preferences
                                            .useNewFormula ? newISF.description : (dynamicISF ?? 0).description
                                    )
                                } else {
                                    Text((
                                        !state.settingsManager.preferences
                                            .useNewFormula ? newISF.formattedAsMmolL : dynamicISF?.decimalValue.formattedAsMmolL
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
                                        hintLabel = "Autosens"
                                        selectedVerboseHint =
                                            "Autosens automatically adjusts insulin delivery based on how sensitive or resistant you are to insulin at the time of the current loop cycle by analyzing past data to keep blood sugar levels stable.\n\nHow it works: It looks at the last 8-24 hours of data, excluding meal-related changes, and adjusts insulin settings like basal rates and targets when needed to match your sensitivity or resistance to insulin.\n\nWhat it adjusts: Autosens modifies Insulin Sensitivity Factor (ISF), basal rates, and target blood sugar levels. It doesn’t account for carbs but adjusts for insulin effectiveness based on patterns in your glucose data.\n\nKey limitations: Autosens has safety limits determined by your Autosens Max and Autosens Min settings. These settings prevent over-adjusting.\n\nAutosens functions alongside certain settings, like Super Micro Bolus (SMB). Other settings, like Dynamic ISF, alter portions of the Autosens formula. Please review the in-app hints for the Algorithm Settings prior to enabling them to understand how they may influence it."
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

                SettingInputSection(
                    decimalValue: $state.autosensMax,
                    booleanValue: $booleanPlaceholder,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0
                            hintLabel = NSLocalizedString("Autosens Max", comment: "Autosens Max")
                        }
                    ),
                    units: state.units,
                    type: .decimal("autosensMax"),
                    label: NSLocalizedString("Autosens Max", comment: "Autosens Max"),
                    miniHint: "Lorem ipsum dolor sit amet, consetetur sadipscing elitr.",
                    verboseHint: NSLocalizedString(
                        "This is a multiplier cap for autosens (and autotune) to set a 20% max limit on how high the autosens ratio can be, which in turn determines how high autosens can adjust basals, how low it can adjust ISF, and how low it can set the BG target.",
                        comment: "Autosens Max"
                    ),
                    headerText: "Glucose Deviations Algorithm"
                )

                SettingInputSection(
                    decimalValue: $state.autosensMin,
                    booleanValue: $booleanPlaceholder,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0
                            hintLabel = NSLocalizedString("Autosens Min", comment: "Autosens Min")
                        }
                    ),
                    units: state.units,
                    type: .decimal("autosensMin"),
                    label: NSLocalizedString("Autosens Min", comment: "Autosens Min"),
                    miniHint: "Lorem ipsum dolor sit amet, consetetur sadipscing elitr.",
                    verboseHint: NSLocalizedString(
                        "The other side of the autosens safety limits, putting a cap on how low autosens can adjust basals, and how high it can adjust ISF and BG targets.",
                        comment: "Autosens Min"
                    )
                )

                SettingInputSection(
                    decimalValue: $decimalPlaceholder,
                    booleanValue: $state.rewindResetsAutosens,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0
                            hintLabel = NSLocalizedString("Rewind Resets Autosens", comment: "Rewind Resets Autosens")
                        }
                    ),
                    units: state.units,
                    type: .boolean,
                    label: NSLocalizedString("Rewind Resets Autosens", comment: "Rewind Resets Autosens"),
                    miniHint: "Lorem ipsum dolor sit amet, consetetur sadipscing elitr.",
                    verboseHint: NSLocalizedString(
                        "This feature, enabled by default, resets the autosens ratio to neutral when you rewind your pump, on the assumption that this corresponds to a probable site change. Autosens will begin learning sensitivity anew from the time of the rewind, which may take up to 6 hours. If you usually rewind your pump independently of site changes, you may want to consider disabling this feature.",
                        comment: "Rewind Resets Autosens"
                    )
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
            .scrollContentBackground(.hidden).background(appState.trioBackgroundColor(for: colorScheme))
            .onAppear(perform: configureView)
            .navigationTitle("Autosens")
            .navigationBarTitleDisplayMode(.automatic)
        }
    }
}
