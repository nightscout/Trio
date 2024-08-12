import SwiftUI
import Swinject

extension SMBSettings {
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
                            selectedVerboseHint = $0
                            hintLabel = NSLocalizedString("Enable SMB Always", comment: "Enable SMB Always")
                        }
                    ),
                    units: state.units,
                    type: .boolean,
                    label: NSLocalizedString("Enable SMB Always", comment: "Enable SMB Always"),
                    miniHint: "Lorem ipsum dolor sit amet, consetetur sadipscing elitr.",
                    verboseHint: NSLocalizedString(
                        "Defaults to false. When true, always enable supermicrobolus (unless disabled by high temptarget).",
                        comment: "Enable SMB Always"
                    ),
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
                                selectedVerboseHint = $0
                                hintLabel = NSLocalizedString("Enable SMB With COB", comment: "Enable SMB With COB")
                            }
                        ),
                        units: state.units,
                        type: .boolean,
                        label: NSLocalizedString("Enable SMB With COB", comment: "Enable SMB With COB"),
                        miniHint: "Lorem ipsum dolor sit amet, consetetur sadipscing elitr.",
                        verboseHint: NSLocalizedString(
                            "This enables supermicrobolus (SMB) while carbs on board (COB) are positive.",
                            comment: "Enable SMB With COB"
                        )
                    )

                    SettingInputSection(
                        decimalValue: $decimalPlaceholder,
                        booleanValue: $state.enableSMBWithTemptarget,
                        shouldDisplayHint: $shouldDisplayHint,
                        selectedVerboseHint: Binding(
                            get: { selectedVerboseHint },
                            set: {
                                selectedVerboseHint = $0
                                hintLabel = NSLocalizedString("Enable SMB With Temptarget", comment: "Enable SMB With Temptarget")
                            }
                        ),
                        units: state.units,
                        type: .boolean,
                        label: NSLocalizedString("Enable SMB With Temptarget", comment: "Enable SMB With Temptarget"),
                        miniHint: "Lorem ipsum dolor sit amet, consetetur sadipscing elitr.",
                        verboseHint: NSLocalizedString(
                            "This enables supermicrobolus (SMB) with eating soon / low temp targets. With this feature enabled, any temporary target below 100mg/dL, such as a temp target of 99 (or 80, the typical eating soon target) will enable SMB.",
                            comment: "Enable SMB With Temptarget"
                        )
                    )

                    SettingInputSection(
                        decimalValue: $decimalPlaceholder,
                        booleanValue: $state.enableSMBAfterCarbs,
                        shouldDisplayHint: $shouldDisplayHint,
                        selectedVerboseHint: Binding(
                            get: { selectedVerboseHint },
                            set: {
                                selectedVerboseHint = $0
                                hintLabel = NSLocalizedString("Enable SMB After Carbs", comment: "Enable SMB After Carbs")
                            }
                        ),
                        units: state.units,
                        type: .boolean,
                        label: NSLocalizedString("Enable SMB After Carbs", comment: "Enable SMB After Carbs"),
                        miniHint: "Lorem ipsum dolor sit amet, consetetur sadipscing elitr.",
                        verboseHint: NSLocalizedString(
                            "Defaults to false. When true, enables supermicrobolus (SMB) for 6h after carbs, even with 0 carbs on board (COB).",
                            comment: "Enable SMB After Carbs"
                        )
                    )

                    SettingInputSection(
                        decimalValue: $decimalPlaceholder,
                        booleanValue: $state.allowSMBWithHighTemptarget,
                        shouldDisplayHint: $shouldDisplayHint,
                        selectedVerboseHint: Binding(
                            get: { selectedVerboseHint },
                            set: {
                                selectedVerboseHint = $0
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
                        miniHint: "Lorem ipsum dolor sit amet, consetetur sadipscing elitr.",
                        verboseHint: NSLocalizedString(
                            "Defaults to false. When true, allows supermicrobolus (if otherwise enabled) even with high temp targets (> 100 mg/dl).",
                            comment: "Allow SMB With High Temptarget"
                        )
                    )

                    SettingInputSection(
                        decimalValue: $state.enableSMB_high_bg_target,
                        booleanValue: $state.enableSMB_high_bg,
                        shouldDisplayHint: $shouldDisplayHint,
                        selectedVerboseHint: Binding(
                            get: { selectedVerboseHint },
                            set: {
                                selectedVerboseHint = $0
                                hintLabel = NSLocalizedString("Enable SMB With High BG", comment: "Enable SMB With High BG")
                            }
                        ),
                        units: state.units,
                        type: .conditionalDecimal("enableSMB_high_bg_target"),
                        label: NSLocalizedString("Enable SMB With High BG", comment: "Enable SMB With High BG"),
                        conditionalLabel: "High BG Target",
                        miniHint: "Lorem ipsum dolor sit amet, consetetur sadipscing elitr.",
                        verboseHint: NSLocalizedString(
                            "Enable SMBs when a high BG is detected, based on the high BG target (adjusted or profile)",
                            comment: "Enable SMB With High BG"
                        )
                    )

                    SettingInputSection(
                        decimalValue: $decimalPlaceholder,
                        booleanValue: $state.enableUAM,
                        shouldDisplayHint: $shouldDisplayHint,
                        selectedVerboseHint: Binding(
                            get: { selectedVerboseHint },
                            set: {
                                selectedVerboseHint = $0
                                hintLabel = NSLocalizedString("Enable UAM", comment: "Enable UAM")
                            }
                        ),
                        units: state.units,
                        type: .boolean,
                        label: NSLocalizedString("Enable UAM", comment: "Enable UAM"),
                        miniHint: "Lorem ipsum dolor sit amet, consetetur sadipscing elitr.",
                        verboseHint: NSLocalizedString(
                            "With this option enabled, the SMB algorithm can recognize unannounced meals. This is helpful, if you forget to tell Trio about your carbs or estimate your carbs wrong and the amount of entered carbs is wrong or if a meal with lots of fat and protein has a longer duration than expected. Without any carb entry, UAM can recognize fast glucose increasments caused by carbs, adrenaline, etc, and tries to adjust it with SMBs. This also works the opposite way: if there is a fast glucose decreasement, it can stop SMBs earlier.",
                            comment: "Enable UAM"
                        )
                    )
                }

                SettingInputSection(
                    decimalValue: $state.maxSMBBasalMinutes,
                    booleanValue: $booleanPlaceholder,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0
                            hintLabel = NSLocalizedString("Max SMB Basal Minutes", comment: "Max SMB Basal Minutes")
                        }
                    ),
                    units: state.units,
                    type: .decimal("maxSMBBasalMinutes"),
                    label: NSLocalizedString("Max SMB Basal Minutes", comment: "Max SMB Basal Minutes"),
                    miniHint: "Lorem ipsum dolor sit amet, consetetur sadipscing elitr.",
                    verboseHint: NSLocalizedString(
                        "Defaults to start at 30. This is the maximum minutes of basal that can be delivered as a single SMB with uncovered COB. This gives the ability to make SMB more aggressive if you choose. It is recommended that the value is set to start at 30, in line with the default, and if you choose to increase this value, do so in no more than 15 minute increments, keeping a close eye on the effects of the changes. It is not recommended to set this value higher than 90 mins, as this may affect the ability for the algorithm to safely zero temp. It is also recommended that pushover is used when setting the value to be greater than default, so that alerts are generated for any predicted lows or highs.",
                        comment: "Max SMB Basal Minutes"
                    )
                )

                SettingInputSection(
                    decimalValue: $state.maxUAMSMBBasalMinutes,
                    booleanValue: $booleanPlaceholder,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0
                            hintLabel = NSLocalizedString("Max UAM SMB Basal Minutes", comment: "Max UAM SMB Basal Minutes")
                        }
                    ),
                    units: state.units,
                    type: .decimal("maxUAMSMBBasalMinutes"),
                    label: NSLocalizedString("Max UAM SMB Basal Minutes", comment: "Max UAM SMB Basal Minutes"),
                    miniHint: "Lorem ipsum dolor sit amet, consetetur sadipscing elitr.",
                    verboseHint: NSLocalizedString(
                        "Defaults to start at 30. This is the maximum minutes of basal that can be delivered by UAM as a single SMB when IOB exceeds COB. This gives the ability to make UAM more or less aggressive if you choose. It is recommended that the value is set to start at 30, in line with the default, and if you choose to increase this value, do so in no more than 15 minute increments, keeping a close eye on the effects of the changes. Reducing the value will cause UAM to dose less insulin for each SMB. It is not recommended to set this value higher than 60 mins, as this may affect the ability for the algorithm to safely zero temp. It is also recommended that pushover is used when setting the value to be greater than default, so that alerts are generated for any predicted lows or highs.",
                        comment: "Max UAM SMB Basal Minutes"
                    )
                )

                SettingInputSection(
                    decimalValue: $state.maxDeltaBGthreshold,
                    booleanValue: $booleanPlaceholder,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0
                            hintLabel = NSLocalizedString("Max Delta-BG Threshold SMB", comment: "Max Delta-BG Threshold")
                        }
                    ),
                    units: state.units,
                    type: .decimal("maxDeltaBGthreshold"),
                    label: NSLocalizedString("Max Delta-BG Threshold SMB", comment: "Max Delta-BG Threshold"),
                    miniHint: "Lorem ipsum dolor sit amet, consetetur sadipscing elitr.",
                    verboseHint: NSLocalizedString(
                        "Defaults to 0.2 (20%). Maximum positive percentual change of BG level to use SMB, above that will disable SMB. Hardcoded cap of 40%. For UAM fully-closed-loop 30% is advisable. Observe in log and popup (maxDelta 27 > 20% of BG 100 - disabling SMB!).",
                        comment: "Max Delta-BG Threshold"
                    )
                )

                SettingInputSection(
                    decimalValue: $state.smbDeliveryRatio,
                    booleanValue: $booleanPlaceholder,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0
                            hintLabel = NSLocalizedString("SMB DeliveryRatio", comment: "SMB DeliveryRatio")
                        }
                    ),
                    units: state.units,
                    type: .decimal("smbDeliveryRatio"),
                    label: NSLocalizedString("SMB DeliveryRatio", comment: "SMB DeliveryRatio"),
                    miniHint: "Lorem ipsum dolor sit amet, consetetur sadipscing elitr.",
                    verboseHint: NSLocalizedString(
                        "Default value: 0.5 This is another key OpenAPS safety cap, and specifies what share of the total insulin required can be delivered as SMB. Increase this experimental value slowly and with caution.",
                        comment: "SMB DeliveryRatio"
                    )
                )

                SettingInputSection(
                    decimalValue: $state.smbInterval,
                    booleanValue: $booleanPlaceholder,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0
                            hintLabel = NSLocalizedString("SMB Interval", comment: "SMB Interval")
                        }
                    ),
                    units: state.units,
                    type: .decimal("smbInterval"),
                    label: NSLocalizedString("SMB Interval", comment: "SMB Interval"),
                    miniHint: "Lorem ipsum dolor sit amet, consetetur sadipscing elitr.",
                    verboseHint: NSLocalizedString(
                        "Minimum duration in minutes for new SMB since last SMB or manual bolus",
                        comment: "SMB Interval"
                    )
                )

                Text("Bolus Increment removed – should be pump derived!")
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
            .navigationTitle("SMB Settings")
            .navigationBarTitleDisplayMode(.automatic)
            .onDisappear {
                state.saveIfChanged()
            }
        }
    }
}
