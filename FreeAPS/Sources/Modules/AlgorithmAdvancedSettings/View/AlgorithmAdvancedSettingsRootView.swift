import SwiftUI
import Swinject

extension AlgorithmAdvancedSettings {
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
                    miniHint: """
                    Temporary basal rates cannot be set higher than this percentage of your LARGEST profile basal rate
                    Default setting: 300%
                    """,
                    verboseHint: VStack(spacing: 10) {
                        Text("Default: 300%").bold()
                        Text(
                            "This limits the automatic adjustment of the temporary basal rate to this value times the highest scheduled basal rate in your basal profile."
                        )
                        Text("Note: If Autotune is enabled, Trio uses Autotune basals instead of scheduled basals.").italic()
                        Text("Warning: Increasing this setting is not advised.").bold().italic()
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
                    miniHint: """
                    Temporary basal rates cannot be set higher than this percentage of the profile basal rate at the time of the loop cycle
                    Default: 400%
                    """,
                    verboseHint: VStack(spacing: 10) {
                        Text("Default: 400%").bold()
                        Text(
                            "This limits the automatic adjustment of the temporary basal rate to this percentage of the current hourly basal rate at the time of the loop cycle."
                        )
                        Text("Note: If Autotune is enabled, Trio uses Autotune basals instead of scheduled basals.").italic()
                        Text("Warning: Increasing this setting is not advised.").bold().italic()
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
                    miniHint: """
                    Number of hours insulin is active in your body
                    Default: 6 hours
                    """,
                    verboseHint: VStack(spacing: 10) {
                        Text("Default: 6 hours").bold()
                        Text("Number of hours insulin will contribute to IOB after dosing.")
                        Text("Tip: It is better to use Custom Peak Time rather than adjust your Duration of Insulin Action (DIA)").italic()
                        Text("Warning: Decreasing this setting is not advised.").bold().italic()
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
                    miniHint: """
                    Time that insulin effect is at it’s highest. Set in minutes since injection.
                    Default: (Set by Insulin Type)
                    """,
                    verboseHint: VStack(spacing: 10) {
                        Text("Default: Set by Insulin Type").bold()
                        Text("Time of maximum glucose lowering effect of insulin. Set in minutes since insulin administration.")
                        VStack(alignment: .leading) {
                            Text("System-Determined Defaults:").bold()
                            Text("𝑼𝒍𝒕𝒓𝒂-𝑹𝒂𝒑𝒊𝒅: 55 minutes (permitted range 35-100 minutes)")
                            Text("𝑹𝒂𝒑𝒊𝒅-𝑨𝒄𝒕𝒊𝒏𝒈: 75 minutes (permitted range 50-120 minutes)")
                        }
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
                    miniHint: """
                    When on, Trio will not send a temp basal command to the pump if the determined basal rate is the same as the scheduled basal
                    Default: OFF
                    """,
                    verboseHint: VStack {
                        Text("Default: OFF").bold()
                        Text("""

                        When enabled, Trio will skip neutral temp basals (those that are the same as your default basal), if no adjustments are needed. 

                        When off, Trio will set temps whenever it can, so it will be easier to see if the system is working.
                        """)
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
                    miniHint: """
                    Automatically resume your insulin pump if you forget to unsuspend it after a zero temp basal expires
                    Default: OFF
                    """,
                    verboseHint: VStack {
                        Text("Default: OFF").bold()
                        Text("""

                        Many people occasionally forget to resume / unsuspend their pump after reconnecting it. If you’re one of them, and you are willing to reliably set a zero temp basal whenever suspending and disconnecting your pump, this feature has your back. If enabled, it will automatically resume / unsuspend the pump if you forget to do so before your zero temp expires. As long as the zero temp is still running, it will leave the pump suspended.

                        """)
                        Text("Applies only to pumps with manual suspend options").italic()
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
                    miniHint: """
                    Replaces any enacted temp basals prior to a pump suspend with a zero temp basal
                    Default: OFF
                    """,
                    verboseHint: VStack {
                        Text("Default: OFF").bold()
                        Text("""

                        Any existing temp basals during times the pump was suspended will be deleted and zero temp basals to negate the profile basal rates during times pump is suspended will be added.

                        """)
                        Text("Applies to only to pumps with manual suspend options").italic()
                    }
                )

                SettingInputSection(
                    decimalValue: $state.autotuneISFAdjustmentFraction,
                    booleanValue: $booleanPlaceholder,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = NSLocalizedString(
                                "Autotune ISF Adjustment Percent",
                                comment: "Autotune ISF Adjustment Percent"
                            )
                        }
                    ),
                    units: state.units,
                    type: .decimal("autotuneISFAdjustmentFraction"),
                    label: NSLocalizedString("Autotune ISF Adjustment Percent", comment: "Autotune ISF Adjustment Percent"),
                    miniHint: """
                    Using Autotune is not advised
                    Default: 50%
                    """,
                    verboseHint: Text(
                        NSLocalizedString(
                            "The default of 50% for this value keeps autotune ISF closer to pump ISF via a weighted average of fullNewISF and pumpISF. 100% allows full adjustment, 0% is no adjustment from pump ISF.",
                            comment: "Autotune ISF Adjustment Percent"
                        )
                    )
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
                    miniHint: """
                    Set the default rate of carb absorption when no clear impact on blood glucose is visible
                    Default: 8 mg/dL/5min
                    """,
                    verboseHint: VStack {
                        Text("Default: 8 mg/dL/5min").bold()
                        Text("""

                        The Min 5m Carbimpact setting determines the default expected glucose rise (in mg/dL) over a 5-minute period from carbs when the system cannot detect clear absorption from your blood glucose levels. 

                        The default value of 8 mg/dL per 5 minutes corresponds to an absorption rate of 24g of carbs per hour. 

                        This setting helps the system estimate how much glucose your body is absorbing, even when it’s not immediately visible in your glucose data, ensuring more accurate insulin dosing during carb absorption.
                        """)
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
                    miniHint: """
                    Set the percentage of unabsorbed carbs that will be assumed to absorb over 4 hours if no absorption is detected
                    Default: 100%
                    """,
                    verboseHint: VStack {
                        Text("Default: 100%").bold()
                        Text("""

                        The Remaining Carbs Percentage setting helps estimate how many carbs from a meal will still be absorbed if your glucose readings don’t show clear carb absorption. This percentage, applied to the entered carbs, will be spread over 4 hours. It’s useful when the system can’t detect carb absorption from blood glucose data, providing a fallback estimate to prevent under-dosing.
                        """)
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
                    miniHint: """
                    Set the maximum amount of carbs assumed to absorb over 4 hours if no absorption is detected
                    Default: 90g
                    """,
                    verboseHint: VStack {
                        Text("Default: 90g").bold()
                        Text("""

                        The Remaining Carbs Cap defines the upper limit for how many carbs the system will assume are absorbing over 4 hours, even when there’s no clear sign of absorption from your glucose readings.

                        This cap prevents the system from overestimating how much insulin is needed when carb absorption isn’t visible, offering a safeguard for accurate dosing.
                        """)
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
                    miniHint: """
                    Increase glucose target by this percent when relying on noisy CGM data
                    Default: 130%
                    """,
                    verboseHint: VStack {
                        Text("Default: 130%").bold()
                        Text("""

                        The Noisy CGM Target Multiplier increases your glucose target when the system detects noisy or raw CGM data. By default, the target is increased by 130% to account for the less reliable glucose readings.

                        This helps reduce the risk of incorrect insulin dosing based on inaccurate sensor data, ensuring safer insulin adjustments during periods of poor CGM accuracy.
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
            .navigationTitle("Additionals")
            .navigationBarTitleDisplayMode(.automatic)
            .onDisappear {
                state.saveIfChanged()
            }
        }
    }
}
