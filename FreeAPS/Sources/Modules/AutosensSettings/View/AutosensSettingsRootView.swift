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
                                    "This is a snapshot in time and should not be used as your ISF setting."
                                )
                                .font(.footnote)
                                .foregroundColor(.secondary)
                                .lineLimit(nil)
                                Spacer()
                                Button(
                                    action: {
                                        hintLabel = "Autosens"
                                        selectedVerboseHint =
                                            "Autosens automatically adjusts insulin delivery based on how sensitive or resistant you are to insulin, by analyzing past data to keep blood sugar levels stable.\n\nHow it works: It looks at the last 8-24 hours of data, excluding meal-related changes, and adjusts insulin settings like basal rates and targets when needed to match your sensitivity or resistance to insulin.\n\nWhat it adjusts: Autosens modifies insulin sensitivity factor (ISF), basal rates, and target blood sugar levels. It doesn’t account for carbs but adjusts for insulin effectiveness based on patterns in your glucose data.\n\nKey limitations: Autosens has safety limits (1.2 for resistance and 0.7 for sensitivity) to prevent over-adjusting, and it works alongside or can be disabled by other settings like Autotune or advanced target adjustments."
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
