import SwiftUI
import Swinject

extension SMBSettings {
    struct RootView: BaseView {
        let resolver: Resolver
        @State var state = StateModel()
        @State private var shouldDisplayHint: Bool = false
        @State var hintDetent = PresentationDetent.large
        @State var selectedVerboseHint: AnyView?
        @State var hintLabel: String?
        @State private var decimalPlaceholder: Decimal = 0.0
        @State private var booleanPlaceholder: Bool = false

        @Environment(\.colorScheme) var colorScheme
        @EnvironmentObject var appIcons: Icons

        private var color: LinearGradient {
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
                            hintLabel = NSLocalizedString("Enable SMB Always", comment: "Enable SMB Always")
                        }
                    ),
                    units: state.units,
                    type: .boolean,
                    label: NSLocalizedString("Enable SMB Always", comment: "Enable SMB Always"),
                    miniHint: """
                    Allow SMBs at all times except when a high Temp Target is set
                    Default: OFF
                    """,
                    verboseHint: VStack {
                        Text("Default: OFF").bold()
                        Text("""

                        When enabled, Super Micro Boluses (SMBs) will always be allowed if dosing calculations determine insulin is needed via the SMB delivery method, except in instances where a high Temp Target is set.
                        """)
                    },
                    headerText: "Super-Micro-Bolus"
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
                                hintLabel = NSLocalizedString("Enable SMB With COB", comment: "Enable SMB With COB")
                            }
                        ),
                        units: state.units,
                        type: .boolean,
                        label: NSLocalizedString("Enable SMB With COB", comment: "Enable SMB With COB"),
                        miniHint: """
                        Allow SMB when carbs are on board
                        Default: OFF
                        """,
                        verboseHint: VStack {
                            Text("Default: OFF").bold()
                            Text("""

                            When the carb on board (COB) forecast line is active, enabling this feature allows Trio to use Super Micro Boluses (SMB) to deliver the insulin required.

                            """)
                            Text(
                                "If this is enabled and the criteria is met, SMBs could be utilized regardless of other SMB settings being enabled or not."
                            )
                            .italic()
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
                                hintLabel = NSLocalizedString("Enable SMB With Temptarget", comment: "Enable SMB With Temptarget")
                            }
                        ),
                        units: state.units,
                        type: .boolean,
                        label: NSLocalizedString("Enable SMB With Temptarget", comment: "Enable SMB With Temptarget"),
                        miniHint: """
                        Allow SMB when a manual Temporary Target is set under 100 mg/dL (5.5 mmol/L)
                        Default: OFF
                        """,
                        verboseHint: VStack {
                            Text("Default: OFF").bold()
                            Text("""

                            Enabling this feature allows Trio to deliver insulin required using Super Micro Boluses (SMB) at times when a manual Temporary Target under 100 mg/dL (5.5 mmol/L) is set.

                            """)
                            Text(
                                "If this is enabled and the criteria is met, SMBs could be utilized regardless of other SMB settings being enabled or not."
                            )
                            .italic()
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
                                hintLabel = NSLocalizedString("Enable SMB After Carbs", comment: "Enable SMB After Carbs")
                            }
                        ),
                        units: state.units,
                        type: .boolean,
                        label: NSLocalizedString("Enable SMB After Carbs", comment: "Enable SMB After Carbs"),
                        miniHint: """
                        Allow SMB for 6 hrs after carbs are logged
                        Default: OFF
                        """,
                        verboseHint: VStack {
                            Text("Default: OFF").bold()
                            Text("""

                            Enabling this feature allows Trio to deliver insulin required using Super Micro Boluses (SMB) for 6 hours after a carb entry, regardless of whether there are active carbs on board (COB).

                            """)
                            Text(
                                "If this is enabled and the criteria is met, SMBs could be utilized regardless of other SMB settings being enabled or not."
                            )
                            .italic()
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
                                hintLabel = NSLocalizedString("Enable SMB With High BG", comment: "Enable SMB With High BG")
                            }
                        ),
                        units: state.units,
                        type: .conditionalDecimal("enableSMB_high_bg_target"),
                        label: NSLocalizedString("Enable SMB With High BG", comment: "Enable SMB With High BG"),
                        conditionalLabel: "High BG Target",
                        miniHint: """
                        Allow SMB when glucose is above the High BG Target value
                        Default: OFF
                        """,
                        verboseHint: VStack {
                            Text("Default: OFF").bold()
                            Text("""

                            Enabling this feature allows Trio to deliver insulin required using Super Micro Boluses (SMB) when glucose reading is above the value set as High BG Target.

                            """)
                            Text(
                                "If this is enabled and the criteria is met, SMBs could be utilized regardless of other SMB settings being enabled or not."
                            )
                            .italic()
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
                            hintLabel = NSLocalizedString(
                                "Allow SMB With High Temptarget",
                                comment: "Allow SMB With High Temptarget"
                            )
                        }
                    ),
                    units: state.units,
                    type: .boolean,
                    label: NSLocalizedString(
                        "Allow SMB With High Temptarget",
                        comment: "Allow SMB With High Temptarget"
                    ),
                    miniHint: """
                    Allow SMB when a manual Temporary Target is set greater than 100 mg/dL (5.5 mmol/L)
                    Default: OFF
                    """,
                    verboseHint: VStack {
                        Text("Default: OFF").bold()
                        Text("""

                        Enabling this feature allows Trio to deliver insulin required using Super Micro Boluses (SMB) when a manual Temporary Target above 100 mg/dL (5.5 mmol/L) is set.

                        """)
                        Text("""
                        If this is enabled and the criteria is met, SMBs could be utilized regardless of other SMB settings being enabled or not.

                        High Temp Targets are often set when recovering from lows. If you use High Temp Targets for that purpose, this feature should remain disabled. 
                        """).italic()
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
                            hintLabel = NSLocalizedString("Enable UAM", comment: "Enable UAM")
                        }
                    ),
                    units: state.units,
                    type: .boolean,
                    label: NSLocalizedString("Enable UAM", comment: "Enable UAM"),
                    miniHint: """
                    Automatically adjust insulin delivery when carbs are not announced or miscalculated
                    Default: OFF
                    """,
                    verboseHint: VStack {
                        Text("Default: OFF").bold()
                        Text("""

                        Enabling the UAM (Unannounced Meals) feature allows the system to detect and respond to unexpected rises in blood glucose caused by unannounced or miscalculated carbs, meals high in fat or protein, or other factors like adrenaline. 

                        It uses the SMB (Super Micro Bolus) algorithm to deliver insulin in small amounts to correct glucose spikes. UAM also works in reverse, reducing or stopping SMBs if glucose levels drop unexpectedly. 

                        This feature ensures more accurate insulin adjustments even when carb entries are missing or incorrect.

                        """)
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
                            hintLabel = NSLocalizedString("Max SMB Basal Minutes", comment: "Max SMB Basal Minutes")
                        }
                    ),
                    units: state.units,
                    type: .decimal("maxSMBBasalMinutes"),
                    label: NSLocalizedString("Max SMB Basal Minutes", comment: "Max SMB Basal Minutes"),
                    miniHint: """
                    Limits the size of a single Super Micro Bolus (SMB) dose
                    Default: 30 minutes
                    """,
                    verboseHint: VStack {
                        Text("""
                        Default: 30 minutes 
                        (50% current basal rate)
                        """).bold()
                        Text("""

                        This is a limit on the size of a single SMB. One SMB can only be as large as this many minutes of your current profile basal rate.

                        To calculate the maximum SMB allowed based on this setting, use the following formula, where 𝒳 = Max SMB Basal Minutes:
                        """)
                        Text("(𝒳 ÷ 60) × current basal rate").italic()
                        Text("""

                        A Max SMB Basal Minutes setting of 30 minutes means SMBs are limited to 50% of your current basal rate: 
                        """)
                        Text("30min ÷ 60min = 0.5 = 50%").italic()
                        Text("""

                        Increasing this value above 90 minutes may impact Trio's ability to effectively zero temp and prevent lows.

                        """)
                        Text("SMBs must be enabled to use this limit").italic()
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
                            hintLabel = NSLocalizedString("Max UAM Basal Minutes", comment: "Max UAM Basal Minutes")
                        }
                    ),
                    units: state.units,
                    type: .decimal("maxUAMSMBBasalMinutes"),
                    label: NSLocalizedString("Max UAM Basal Minutes", comment: "Max UAM Basal Minutes"),
                    miniHint: """
                    Limits the size of a single Unannounced Meal (UAM) SMB dose
                    Default: 30 minutes
                    """,
                    verboseHint: VStack {
                        Text("""
                        Default: 30 minutes 
                        (50% current basal rate)
                        """).bold()
                        Text("""

                        This is a limit on the size of a single UAM SMB. One UAM SMB can only be as large as this many minutes of your current profile basal rate.

                        To calculate the maximum UAM SMB allowed based on this setting, use the following formula, where 𝒳 = Max UAM SMB Basal Minutes:
                        """)
                        Text("(𝒳 ÷ 60) × current basal rate").italic()
                        Text("""

                        A Max UAM SMB Basal Minutes setting of 30 minutes means SMBs are limited to 50% of your current basal rate:
                        """)
                        Text("30min ÷ 60min = 0.5 = 50%").italic()
                        Text("""

                        Increasing this value above 90 may impact Trio's ability to effectively zero temp and prevent lows.

                        """)
                        Text("UAM SMBs must be enabled to use this limit").italic()
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
                            hintLabel = NSLocalizedString("Max Delta-BG Threshold SMB", comment: "Max Delta-BG Threshold")
                        }
                    ),
                    units: state.units,
                    type: .decimal("maxDeltaBGthreshold"),
                    label: NSLocalizedString("Max Delta-BG Threshold SMB", comment: "Max Delta-BG Threshold"),
                    miniHint: """
                        When the difference between the last two glucose values is larger than this, it will disable SMBs
                        Default: 20%
                        """,
                    verboseHint: VStack {
                        Text("Default: 20% increase").bold()
                        Text("""
                            
                            Maximum allowed positive percentual change in glucose level to permit SMBs. If the difference in glucose is greater than this, Trio will disable SMBs.
                            
                            """)
                        Text("This setting has a hard-coded cap of a 40%").italic()
                    }
                )

                SettingInputSection(
                    decimalValue: $state.smbDeliveryRatio,
                    booleanValue: $booleanPlaceholder,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = NSLocalizedString("SMB DeliveryRatio", comment: "SMB DeliveryRatio")
                        }
                    ),
                    units: state.units,
                    type: .decimal("smbDeliveryRatio"),
                    label: NSLocalizedString("SMB DeliveryRatio", comment: "SMB DeliveryRatio"),
                    miniHint: """
                        Safety limit on what percentage of total calculated insulin required can be administered as an SMB
                        Default: 50%
                        """,
                    verboseHint: VStack {
                        Text("Default: 50%").bold()
                        Text("""
                            
                            Once the total insulin required is calculated, this safety limit specifies what share of the total insulin required can be delivered as an SMB.
                            
                            Due to SMBs occurring every 5 minutes, it is important to set this value to a reasonable level that allows Trio to safely zero temp should dosing needs suddenly change. Increase this value with caution.
                            
                            """)
                        Text("Limited to a range of 30 - 70%").italic()
                    }
                )

                SettingInputSection(
                    decimalValue: $state.smbInterval,
                    booleanValue: $booleanPlaceholder,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = NSLocalizedString("SMB Interval", comment: "SMB Interval")
                        }
                    ),
                    units: state.units,
                    type: .decimal("smbInterval"),
                    label: NSLocalizedString("SMB Interval", comment: "SMB Interval"),
                    miniHint: """
                        Minimum minutes since the last SMB or manual bolus to allow an automated SMB
                        Default: 3 min
                        """,
                    verboseHint: VStack {
                        Text("Default: 3 min").bold()
                        Text("""
                            
                            This is the minimum number of minutes since the last SMB or manual bolus before Trio will permit an automated SMB.
                            
                            For Omnipod Dash, this value can be as low as 3 min. For Omnipod Eros, the value can be as low as 5 min.
                            """)
                    }
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
            .navigationTitle("SMB Settings")
            .navigationBarTitleDisplayMode(.automatic)
            .onDisappear {
                state.saveIfChanged()
            }
        }
    }
}
