import SwiftUI
import Swinject

extension SMBSettings {
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

        var body: some View {
            List {
                SettingInputSection(
                    decimalValue: $decimalPlaceholder,
                    booleanValue: $state.enableSMBAlways,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = String(localized: "Enable SMB Always", comment: "Enable SMB Always")
                        }
                    ),
                    units: state.units,
                    type: .boolean,
                    label: String(localized: "Enable SMB Always", comment: "Enable SMB Always"),
                    miniHint: String(localized: "Allow SMBs at all times except when a high Temp Target is set."),
                    verboseHint: VStack(alignment: .leading, spacing: 10) {
                        Text("Default: OFF").bold()
                        Text(
                            "When enabled, Super Micro Boluses (SMBs) will always be allowed if dosing calculations determine insulin is needed via the SMB delivery method, except when a high Temp Target is set. Enabling SMB Always will remove redundant \"Enable SMB\" options when this setting is enacted."
                        )
                        Text(
                            "Note: If you would like to allow SMBs when a high Temp Target is set, enable the \"Allow SMBs with High Temptarget\" setting."
                        )
                    },
                    headerText: String(localized: "Super-Micro-Bolus")
                )

                if !state.enableSMBAlways {
                    SettingInputSection(
                        decimalValue: $decimalPlaceholder,
                        booleanValue: $state.enableSMBWithCOB,
                        shouldDisplayHint: $shouldDisplayHint,
                        selectedVerboseHint: Binding(
                            get: { selectedVerboseHint },
                            set: {
                                selectedVerboseHint = $0.map { AnyView($0) }
                                hintLabel = String(localized: "Enable SMB With COB", comment: "Enable SMB With COB")
                            }
                        ),
                        units: state.units,
                        type: .boolean,
                        label: String(localized: "Enable SMB With COB", comment: "Enable SMB With COB"),
                        miniHint: String(localized: "Allow SMB when carbs are on board."),
                        verboseHint:
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Default: OFF").bold()
                            Text(
                                "When there are carbs on board (COB > 0), enabling this feature allows Trio to use Super Micro Boluses (SMB) to deliver the insulin required."
                            )
                            Text(
                                "Note: If this is enabled and the criteria are met, SMBs could be utilized regardless of other SMB settings being enabled or not."
                            )
                        }
                    )

                    SettingInputSection(
                        decimalValue: $decimalPlaceholder,
                        booleanValue: $state.enableSMBWithTemptarget,
                        shouldDisplayHint: $shouldDisplayHint,
                        selectedVerboseHint: Binding(
                            get: { selectedVerboseHint },
                            set: {
                                selectedVerboseHint = $0.map { AnyView($0) }
                                hintLabel = String(localized: "Enable SMB With Temptarget", comment: "Enable SMB With Temptarget")
                            }
                        ),
                        units: state.units,
                        type: .boolean,
                        label: String(localized: "Enable SMB With Temptarget", comment: "Enable SMB With Temptarget"),
                        miniHint: String(
                            localized: "Allow SMB when a manual Temporary Target is set under \(state.units == .mgdL ? "100" : 100.formattedAsMmolL) \(state.units.rawValue)."
                        ),
                        verboseHint:
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Default: OFF").bold()
                            Text(
                                "Enabling this feature allows Trio to deliver insulin required using Super Micro Boluses (SMB) at times when a manual Temporary Target under \(state.units == .mgdL ? "100" : 100.formattedAsMmolL) \(state.units.rawValue) is set."
                            )
                            Text(
                                "Note: If this is enabled and the criteria are met, SMBs could be utilized regardless of other SMB settings being enabled or not."
                            )
                        }
                    )

                    SettingInputSection(
                        decimalValue: $decimalPlaceholder,
                        booleanValue: $state.enableSMBAfterCarbs,
                        shouldDisplayHint: $shouldDisplayHint,
                        selectedVerboseHint: Binding(
                            get: { selectedVerboseHint },
                            set: {
                                selectedVerboseHint = $0.map { AnyView($0) }
                                hintLabel = String(localized: "Enable SMB After Carbs", comment: "Enable SMB After Carbs")
                            }
                        ),
                        units: state.units,
                        type: .boolean,
                        label: String(localized: "Enable SMB After Carbs", comment: "Enable SMB After Carbs"),
                        miniHint: String(localized: "Allow SMB for 6 hrs after a carb entry."),
                        verboseHint:
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Default: OFF").bold()
                            Text(
                                "Enabling this feature allows Trio to deliver insulin required using Super Micro Boluses (SMB) for 6 hours after a carb entry, regardless of whether there are active carbs on board (COB)."
                            )
                            Text(
                                "Note: If this is enabled and the criteria are met, SMBs could be utilized regardless of other SMB settings being enabled or not."
                            )
                        }
                    )

                    SettingInputSection(
                        decimalValue: $state.enableSMB_high_bg_target,
                        booleanValue: $state.enableSMB_high_bg,
                        shouldDisplayHint: $shouldDisplayHint,
                        selectedVerboseHint: Binding(
                            get: { selectedVerboseHint },
                            set: {
                                selectedVerboseHint = $0.map { AnyView($0) }
                                hintLabel = String(
                                    localized: "Enable SMB With High Glucose",
                                    comment: "Enable SMB With High Glucose"
                                )
                            }
                        ),
                        units: state.units,
                        type: .conditionalDecimal("enableSMB_high_bg_target"),
                        label: String(localized: "Enable SMB With High Glucose", comment: "Enable SMB With High Glucose"),
                        conditionalLabel: String(localized: "High Glucose Target"),
                        miniHint: String(localized: "Allow SMB when glucose is above the High Glucose Target value."),
                        verboseHint:
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Default: OFF").bold()
                            Text(
                                "Enabling this feature allows Trio to deliver insulin required using Super Micro Boluses (SMB) when glucose reading is above the value set as High Glucose Target."
                            )
                            Text(
                                "Note: If this is enabled and the criteria are met, SMBs could be utilized regardless of other SMB settings being enabled or not."
                            )
                        }
                    )
                }

                SettingInputSection(
                    decimalValue: $decimalPlaceholder,
                    booleanValue: $state.allowSMBWithHighTemptarget,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = String(
                                localized:
                                "Allow SMB With High Temptarget",
                                comment: "Allow SMB With High Temptarget"
                            )
                        }
                    ),
                    units: state.units,
                    type: .boolean,
                    label: String(
                        localized:
                        "Allow SMB With High Temptarget",
                        comment: "Allow SMB With High Temptarget"
                    ),
                    miniHint: String(
                        localized: "Allow SMB when a manual Temporary Target is set greater than \(state.units == .mgdL ? "100" : 100.formattedAsMmolL) \(state.units.rawValue)."
                    ),
                    verboseHint:
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Default: OFF").bold()
                        Text(
                            "Enabling this feature allows Trio to deliver insulin required using Super Micro Boluses (SMB) when a manual Temporary Target above \(state.units == .mgdL ? "100" : 100.formattedAsMmolL) \(state.units.rawValue) is set."
                        )
                        Text(
                            "Note: If this is enabled and the criteria are met, SMBs could be utilized regardless of other SMB settings being enabled or not."
                        )
                        Text(
                            "Warning: High Temp Targets are often set when recovering from lows. If you use High Temp Targets for that purpose, this feature should remain disabled."
                        ).bold()
                    }
                )

                SettingInputSection(
                    decimalValue: $decimalPlaceholder,
                    booleanValue: $state.enableUAM,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = String(localized: "Enable UAM", comment: "Enable UAM")
                        }
                    ),
                    units: state.units,
                    type: .boolean,
                    label: String(localized: "Enable UAM", comment: "Enable UAM"),
                    miniHint: String(localized: "Enable Unannounced Meals SMB."),
                    verboseHint:
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Default: OFF").bold()
                        Text(
                            "Enabling the UAM (Unannounced Meals) feature allows the system to detect and respond to unexpected rises in glucose readings caused by unannounced or miscalculated carbs, meals high in fat or protein, or other factors like adrenaline."
                        )
                        Text(
                            "It uses the SMB (Super Micro Bolus) algorithm to deliver insulin in small amounts to correct glucose spikes. UAM also works in reverse, reducing or stopping SMBs if glucose levels drop unexpectedly."
                        )
                        Text(
                            "This feature ensures more accurate insulin adjustments when carb entries are missing or incorrect."
                        )
                    }
                )

                SettingInputSection(
                    decimalValue: $state.maxSMBBasalMinutes,
                    booleanValue: $booleanPlaceholder,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = String(localized: "Max SMB Basal Minutes", comment: "Max SMB Basal Minutes")
                        }
                    ),
                    units: state.units,
                    type: .decimal("maxSMBBasalMinutes"),
                    label: String(localized: "Max SMB Basal Minutes", comment: "Max SMB Basal Minutes"),
                    miniHint: String(localized: "Limits the size of a single Super Micro Bolus (SMB) dose."),
                    verboseHint: VStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 10) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Default: 30 minutes").bold()
                                Text("(50% current basal rate)").bold()
                            }
                            VStack(alignment: .leading, spacing: 10) {
                                Text(
                                    "This is a limit on the size of a single SMB. One SMB can only be as large as this many minutes of your current profile basal rate."
                                )
                                Text(
                                    "To calculate the maximum SMB allowed based on this setting, use the following formula:"
                                )
                            }
                        }
                        VStack(alignment: .center, spacing: 5) {
                            Text(
                                "𝒳 = Max SMB Basal Minutes"
                            )
                            Text("(𝒳 / 60) × current basal rate")
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Text(
                                "Warning: Increasing this value above 90 minutes may impact Trio's ability to effectively zero temp and prevent lows."
                            ).bold()
                            Text("Note: SMBs must be enabled to use this limit.")
                        }
                    }
                )

                SettingInputSection(
                    decimalValue: $state.maxUAMSMBBasalMinutes,
                    booleanValue: $booleanPlaceholder,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = String(localized: "Max UAM Basal Minutes", comment: "Max UAM Basal Minutes")
                        }
                    ),
                    units: state.units,
                    type: .decimal("maxUAMSMBBasalMinutes"),
                    label: String(localized: "Max UAM Basal Minutes", comment: "Max UAM Basal Minutes"),
                    miniHint: String(localized: "Limits the size of a single Unannounced Meal (UAM) SMB dose."),
                    verboseHint: VStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 10) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Default: 30 minutes").bold()
                                Text("(50% current basal rate)").bold()
                            }
                            VStack(alignment: .leading, spacing: 10) {
                                Text(
                                    "This is a limit on the size of a single UAM SMB. One UAM SMB can only be as large as this many minutes of your current profile basal rate."
                                )
                                Text(
                                    "To calculate the maximum UAM SMB allowed based on this setting, use the following formula:"
                                )
                            }
                        }
                        VStack(alignment: .center, spacing: 5) {
                            Text(
                                "𝒳 = Max UAM SMB Basal Minutes"
                            )
                            Text("(𝒳 / 60) × current basal rate")
                        }
                        VStack(alignment: .leading, spacing: 10) {
                            Text(
                                "Warning: Increasing this value above 90 minutes may impact Trio's ability to effectively zero temp and prevent lows."
                            ).bold()
                            Text("Note: UAM SMBs must be enabled to use this limit.")
                        }
                    }
                )

                SettingInputSection(
                    decimalValue: $state.maxDeltaBGthreshold,
                    booleanValue: $booleanPlaceholder,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = String(
                                localized: "Max. Allowed Glucose Rise for SMB",
                                comment: "Max. Allowed Glucose Rise for SMB, formerly Max Delta-BG Threshold"
                            )
                        }
                    ),
                    units: state.units,
                    type: .decimal("maxDeltaBGthreshold"),
                    label: String(
                        localized: "Max. Allowed Glucose Rise for SMB",
                        comment: "Max. Allowed Glucose Rise for SMB, formerly Max Delta-BG Threshold"
                    ),
                    miniHint: String(localized: "Disables SMBs if last two glucose values differ by more than this percent."),
                    verboseHint:
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Default: 20% increase").bold()
                        Text(
                            "Maximum allowed positive percent change in glucose level to permit SMBs. If the difference in glucose is greater than this, Trio will disable SMBs."
                        )
                        Text(
                            "This is a safety limitation to avoid high SMB doses when glucose is rising abnormally fast, such as after a meal or with a very jumpy CGM sensor."
                        )
                        Text("Note: This setting has a hard-coded cap of 40%")
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
            .navigationTitle("SMB Settings")
            .navigationBarTitleDisplayMode(.automatic)
        }
    }
}
