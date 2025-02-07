import SwiftUI
import Swinject

extension AlgorithmAdvancedSettings {
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
                Section(
                    header: Text("DISCLAIMER"),
                    content: {
                        VStack(alignment: .leading) {
                            Text(
                                "The settings in this section typically do not require ANY modifications. Do not alter them without a solid understanding of what you are changing and the full impact it will have on the algorithm."
                            ).bold()
                        }
                    }

                ).listRowBackground(Color.tabBar)

                SettingInputSection(
                    decimalValue: $state.maxDailySafetyMultiplier,
                    booleanValue: $booleanPlaceholder,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = NSLocalizedString("Max Daily Safety Multiplier", comment: "Max Daily Safety Multiplier")
                        }
                    ),
                    units: state.units,
                    type: .decimal("maxDailySafetyMultiplier"),
                    label: NSLocalizedString("Max Daily Safety Multiplier", comment: "Max Daily Safety Multiplier"),
                    miniHint: "Limits temporary basal rates to this percentage of your largest basal rate.",
                    verboseHint:
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Default: 300%").bold()
                        Text(
                            "This setting restricts the maximum temporary basal rate Trio can set. At the default of 300%, it caps it at 3 times your highest programmed basal rate."
                        )
                        Text("It serves as a safety limit, ensuring no temporary basal rates exceed safe levels.")
                        Text("Warning: Increasing this setting is not advised.").bold()
                    }
                )

                SettingInputSection(
                    decimalValue: $state.currentBasalSafetyMultiplier,
                    booleanValue: $booleanPlaceholder,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = NSLocalizedString(
                                "Current Basal Safety Multiplier",
                                comment: "Current Basal Safety Multiplier"
                            )
                        }
                    ),
                    units: state.units,
                    type: .decimal("currentBasalSafetyMultiplier"),
                    label: NSLocalizedString("Current Basal Safety Multiplier", comment: "Current Basal Safety Multiplier"),
                    miniHint: "Limits temporary basal rates to this percentage of the current basal rate.",
                    verboseHint:
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Default: 400%").bold()
                        Text(
                            "This limits the automatic adjustment of the temporary basal rate to this percentage of the current hourly profile basal rate at the time of the loop cycle."
                        )
                        Text(
                            "This prevents excessive dosing, especially during times of variable insulin sensitivity, enhancing safety."
                        )
                        Text("Warning: Increasing this setting is not advised.").bold()
                    }
                )

                SettingInputSection(
                    decimalValue: $state.insulinActionCurve,
                    booleanValue: $booleanPlaceholder,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = "Duration of Insulin Action"
                        }
                    ),
                    units: state.units,
                    type: .decimal("dia"),
                    label: "Duration of Insulin Action",
                    miniHint: "Number of hours insulin is active in your body.",
                    verboseHint:
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Default: 10 hours").bold()
                        Text(
                            "The Duration of Insulin Action (DIA) defines how long your insulin continues to lower glucose readings after a dose."
                        )
                        Text(
                            "This helps the system accurately track Insulin on Board (IOB), avoiding over- or under-corrections by considering the tail end of insulin's effect."
                        )
                        Text(
                            "Tip: It is better to use Custom Peak Time rather than adjust your Duration of Insulin Action (DIA)."
                        )
                    }
                )

                SettingInputSection(
                    decimalValue: $state.insulinPeakTime,
                    booleanValue: $state.useCustomPeakTime,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = NSLocalizedString("Use Custom Peak Time", comment: "Use Custom Peak Time")
                        }
                    ),
                    units: state.units,
                    type: .conditionalDecimal("insulinPeakTime"),
                    label: NSLocalizedString("Use Custom Peak Time", comment: "Use Custom Peak Time"),
                    conditionalLabel: NSLocalizedString("Insulin Peak Time", comment: "Insulin Peak Time"),
                    miniHint: "Set a custom time for peak insulin effect.",
                    verboseHint:
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Default: Set by Insulin Type").bold()
                        Text(
                            "Insulin Peak Time defines when insulin is most effective in lowering glucose, set in minutes after dosing."
                        )
                        Text(
                            "This peak informs the system when to expect the most potent glucose-lowering effect, helping it predict glucose trends more accurately."
                        )
                        Text("System-Determined Defaults:").bold()
                        Text("Ultra-Rapid: 55 minutes (permitted range 35-100 minutes)")
                        Text("Rapid-Acting: 75 minutes (permitted range 50-120 minutes)")
                    }
                )

                SettingInputSection(
                    decimalValue: $decimalPlaceholder,
                    booleanValue: $state.skipNeutralTemps,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = NSLocalizedString("Skip Neutral Temps", comment: "Skip Neutral Temps")
                        }
                    ),
                    units: state.units,
                    type: .boolean,
                    label: NSLocalizedString("Skip Neutral Temps", comment: "Skip Neutral Temps"),
                    miniHint: "Skip neutral temporary basal rates to reduce MDT pump alerts.",
                    verboseHint:
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Default: OFF").bold()
                        Text(
                            "When Skip Neutral Temps is enabled, Trio will not set neutral basal rates shortly before the hour, minimizing hourly pump alerts on MDT pumps. This can help light sleepers avoid alerts but will delay basal adjustments. This will also only come into effect if SMB's are disabled for whatever reason."
                        )
                        Text(
                            "For most users, leaving this OFF is recommended to ensure consistent basal delivery and loop calculation. If this option is effective, loops will be skipped during the last 5 minutes of the hour."
                        )
                    }
                )

                SettingInputSection(
                    decimalValue: $decimalPlaceholder,
                    booleanValue: $state.unsuspendIfNoTemp,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = NSLocalizedString("Unsuspend If No Temp", comment: "Unsuspend If No Temp")
                        }
                    ),
                    units: state.units,
                    type: .boolean,
                    label: NSLocalizedString("Unsuspend If No Temp", comment: "Unsuspend If No Temp"),
                    miniHint: "Resume pump automatically after suspension.",
                    verboseHint:
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Default: OFF").bold()
                        Text(
                            "Enabling Unsuspend If No Temp allows Trio to resume your pump if you forget, as long as a zero temp basal was set first. This feature ensures insulin delivery restarts if you forget to manually unsuspend, adding a safeguard for pump reconnections."
                        )
                        Text("Note: Applies only to pumps with on-pump suspend options")
                    }
                )

                SettingInputSection(
                    decimalValue: $decimalPlaceholder,
                    booleanValue: $state.suspendZerosIOB,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = NSLocalizedString("Suspend Zeros IOB", comment: "Suspend Zeros IOB")
                        }
                    ),
                    units: state.units,
                    type: .boolean,
                    label: NSLocalizedString("Suspend Zeros IOB", comment: "Suspend Zeros IOB"),
                    miniHint: "Clear temporary basal rates and reset IOB when suspended.",
                    verboseHint:
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Default: OFF").bold()
                        Text(
                            "When Suspend Zeros IOB is enabled, any active temporary basal rates during a pump suspension are reset, with new 0 U/hr temporary basal rates added to counteract those done during suspension."
                        )
                        Text(
                            "This prevents lingering insulin effects when your pump is suspended, ensuring safer management of insulin on board."
                        )
                        Text("Note: Applies only to pumps with on-pump suspend options.")
                    }
                )

                SettingInputSection(
                    decimalValue: $state.min5mCarbimpact,
                    booleanValue: $booleanPlaceholder,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = NSLocalizedString("Min 5m Carb Impact", comment: "Min 5m Carb Impact")
                        }
                    ),
                    units: state.units,
                    type: .decimal("min5mCarbimpact"),
                    label: NSLocalizedString("Min 5m Carb Impact", comment: "Min 5m Carb Impact"),
                    miniHint: "Default impact of carb absorption over a 5 minute interval.",
                    verboseHint:
                    VStack(alignment: .leading, spacing: 10) {
                        Text(
                            "Min 5m Carb Impact sets the expected glucose rise from carbs over 5 minutes when absorption isn't obvious from glucose data."
                        )
                        Text(
                            "The default value of 8 mg/dL per 5 minutes corresponds to an absorption rate of 24 g of carbs per hour."
                        )
                        Text(
                            "This setting helps the system estimate how much glucose your body is absorbing, even when it's not immediately visible in your glucose data, ensuring more accurate insulin dosing during carb absorption."
                        )
                    }
                )

                SettingInputSection(
                    decimalValue: $state.remainingCarbsFraction,
                    booleanValue: $booleanPlaceholder,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = NSLocalizedString("Remaining Carbs Percentage", comment: "Remaining Carbs Percentage")
                        }
                    ),
                    units: state.units,
                    type: .decimal("remainingCarbsFraction"),
                    label: NSLocalizedString("Remaining Carbs Percentage", comment: "Remaining Carbs Percentage"),
                    miniHint: "Percentage of carbs still available if no absorption is detected.",
                    verboseHint:
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Default: 100%").bold()
                        Text(
                            "Remaining Carbs Percentage estimates carbs still absorbing over 4 hours if glucose data doesn't show clear absorption."
                        )
                        Text(
                            "This fallback setting prevents under-dosing by spreading a portion of the entered carbs over time, balancing insulin needs with undetected carb impact."
                        )
                    }
                )

                SettingInputSection(
                    decimalValue: $state.remainingCarbsCap,
                    booleanValue: $booleanPlaceholder,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = NSLocalizedString("Remaining Carbs Cap", comment: "Remaining Carbs Cap")
                        }
                    ),
                    units: state.units,
                    type: .decimal("remainingCarbsCap"),
                    label: NSLocalizedString("Remaining Carbs Cap", comment: "Remaining Carbs Cap"),
                    miniHint: "Maximum amount of carbs still available if no absorption is detected.",
                    verboseHint:
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Default: 90 g").bold()
                        Text(
                            "The Remaining Carbs Cap defines the upper limit for how many carbs the system will assume are absorbing over 4 hours, even when there's no clear sign of absorption from your glucose readings."
                        )
                        Text(
                            "This cap prevents the system from overestimating how much insulin is needed when carb absorption isn't visible, offering a safeguard for accurate dosing."
                        )
                    }
                )

                SettingInputSection(
                    decimalValue: $state.noisyCGMTargetMultiplier,
                    booleanValue: $booleanPlaceholder,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = NSLocalizedString("Noisy CGM Target Multiplier", comment: "Noisy CGM Target Multiplier")
                        }
                    ),
                    units: state.units,
                    type: .decimal("noisyCGMTargetMultiplier"),
                    label: NSLocalizedString("Noisy CGM Target Increase", comment: "Noisy CGM Target Increase"),
                    miniHint: "Percentage increase of glucose target when CGM is inconsistent.",
                    verboseHint:
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Default: 130%").bold()
                        Text(
                            "The Noisy CGM Target Increase raises your glucose target when the system detects noisy or raw CGM data. By default, the target is increased to 130% of your set target glucose to account for the less reliable glucose readings."
                        )
                        Text(
                            "This helps reduce the risk of incorrect insulin dosing based on inaccurate sensor data, ensuring safer insulin adjustments during periods of poor CGM accuracy."
                        )
                        Text("Note: A CGM is considered noisy when it provides inconsistent readings.")
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
                    sheetTitle: "Help"
                )
            }
            .scrollContentBackground(.hidden)
            .background(appState.trioBackgroundColor(for: colorScheme))
            .onAppear(perform: configureView)
            .navigationTitle("Additionals")
            .navigationBarTitleDisplayMode(.automatic)
            .onDisappear {
                state.saveIfChanged()
            }
        }
    }
}
