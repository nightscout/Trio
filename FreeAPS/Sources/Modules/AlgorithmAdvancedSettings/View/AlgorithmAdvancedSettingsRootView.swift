import SwiftUI
import Swinject

extension AlgorithmAdvancedSettings {
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
                Section(
                    header: Text("DISCLAIMER"),
                    content: {
                        VStack(alignment: .leading) {
                            Text(
                                "The settings in this section are designed for advanced expert users and typically do not require ANY modifications."
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
                            selectedVerboseHint = $0
                            hintLabel = NSLocalizedString("Max Daily Safety Multiplier", comment: "Max Daily Safety Multiplier")
                        }
                    ),
                    units: state.units,
                    type: .decimal("maxDailySafetyMultiplier"),
                    label: NSLocalizedString("Max Daily Safety Multiplier", comment: "Max Daily Safety Multiplier"),
                    miniHint: "Lorem ipsum dolor sit amet, consetetur sadipscing elitr.",
                    verboseHint: NSLocalizedString(
                        "This is an important OpenAPS safety limit. The default setting (which is unlikely to need adjusting) is 3. This means that OpenAPS will never be allowed to set a temporary basal rate that is more than 3x the highest hourly basal rate programmed in a user’s pump, or, if enabled, determined by autotune.",
                        comment: "Max Daily Safety Multiplier"
                    )
                )

                SettingInputSection(
                    decimalValue: $state.currentBasalSafetyMultiplier,
                    booleanValue: $booleanPlaceholder,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0
                            hintLabel = NSLocalizedString(
                                "Current Basal Safety Multiplier",
                                comment: "Current Basal Safety Multiplier"
                            )
                        }
                    ),
                    units: state.units,
                    type: .decimal("currentBasalSafetyMultiplier"),
                    label: NSLocalizedString("Current Basal Safety Multiplier", comment: "Current Basal Safety Multiplier"),
                    miniHint: "Lorem ipsum dolor sit amet, consetetur sadipscing elitr.",
                    verboseHint: NSLocalizedString(
                        "This is another important OpenAPS safety limit. The default setting (which is also unlikely to need adjusting) is 4. This means that OpenAPS will never be allowed to set a temporary basal rate that is more than 4x the current hourly basal rate programmed in a user’s pump, or, if enabled, determined by autotune.",
                        comment: "Current Basal Safety Multiplier"
                    )
                )

                SettingInputSection(
                    decimalValue: $state.insulinPeakTime,
                    booleanValue: $state.useCustomPeakTime,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0
                            hintLabel = NSLocalizedString("Use Custom Peak Time", comment: "Use Custom Peak Time")
                        }
                    ),
                    units: state.units,
                    type: .conditionalDecimal("insulinPeakTime"),
                    label: NSLocalizedString("Use Custom Peak Time", comment: "Use Custom Peak Time"),
                    conditionalLabel: NSLocalizedString("Insulin Peak Time", comment: "Insulin Peak Time"),
                    miniHint: "Lorem ipsum dolor sit amet, consetetur sadipscing elitr.",
                    verboseHint: NSLocalizedString(
                        "Defaults to false. Setting to true allows changing insulinPeakTime", comment: "Use Custom Peak Time"
                    ) + NSLocalizedString(
                        "Time of maximum blood glucose lowering effect of insulin, in minutes. Beware: Oref assumes for ultra-rapid (Lyumjev) & rapid-acting (Fiasp) curves minimal (35 & 50 min) and maximal (100 & 120 min) applicable insulinPeakTimes. Using a custom insulinPeakTime outside these bounds will result in issues with Trio, longer loop calculations and possible red loops.",
                        comment: "Insulin Peak Time"
                    )
                )

                SettingInputSection(
                    decimalValue: $decimalPlaceholder,
                    booleanValue: $state.skipNeutralTemps,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0
                            hintLabel = NSLocalizedString("Skip Neutral Temps", comment: "Skip Neutral Temps")
                        }
                    ),
                    units: state.units,
                    type: .boolean,
                    label: NSLocalizedString("Skip Neutral Temps", comment: "Skip Neutral Temps"),
                    miniHint: "Lorem ipsum dolor sit amet, consetetur sadipscing elitr.",
                    verboseHint: NSLocalizedString(
                        "Defaults to false, so that Trio will set temps whenever it can, so it will be easier to see if the system is working, even when you are offline. This means Trio will set a “neutral” temp (same as your default basal) if no adjustments are needed. This is an old setting for OpenAPS to have the options to minimise sounds and notifications from the 'rig', that may wake you up during the night.",
                        comment: "Skip Neutral Temps"
                    )
                )

                SettingInputSection(
                    decimalValue: $decimalPlaceholder,
                    booleanValue: $state.unsuspendIfNoTemp,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0
                            hintLabel = NSLocalizedString("Unsuspend If No Temp", comment: "Unsuspend If No Temp")
                        }
                    ),
                    units: state.units,
                    type: .boolean,
                    label: NSLocalizedString("Unsuspend If No Temp", comment: "Unsuspend If No Temp"),
                    miniHint: "Lorem ipsum dolor sit amet, consetetur sadipscing elitr.",
                    verboseHint: NSLocalizedString(
                        "Many people occasionally forget to resume / unsuspend their pump after reconnecting it. If you’re one of them, and you are willing to reliably set a zero temp basal whenever suspending and disconnecting your pump, this feature has your back. If enabled, it will automatically resume / unsuspend the pump if you forget to do so before your zero temp expires. As long as the zero temp is still running, it will leave the pump suspended.",
                        comment: "Unsuspend If No Temp"
                    )
                )

                SettingInputSection(
                    decimalValue: $decimalPlaceholder,
                    booleanValue: $state.suspendZerosIOB,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0
                            hintLabel = NSLocalizedString("Suspend Zeros IOB", comment: "Suspend Zeros IOB")
                        }
                    ),
                    units: state.units,
                    type: .boolean,
                    label: NSLocalizedString("Suspend Zeros IOB", comment: "Suspend Zeros IOB"),
                    miniHint: "Lorem ipsum dolor sit amet, consetetur sadipscing elitr.",
                    verboseHint: NSLocalizedString(
                        "Default is false. Any existing temp basals during times the pump was suspended will be deleted and 0 temp basals to negate the profile basal rates during times pump is suspended will be added.",
                        comment: "Suspend Zeros IOB"
                    )
                )

                SettingInputSection(
                    decimalValue: $state.autotuneISFAdjustmentFraction,
                    booleanValue: $booleanPlaceholder,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0
                            hintLabel = NSLocalizedString(
                                "Autotune ISF Adjustment Fraction",
                                comment: "Autotune ISF Adjustment Fraction"
                            )
                        }
                    ),
                    units: state.units,
                    type: .decimal("autotuneISFAdjustmentFraction"),
                    label: NSLocalizedString("Autotune ISF Adjustment Fraction", comment: "Autotune ISF Adjustment Fraction"),
                    miniHint: "Lorem ipsum dolor sit amet, consetetur sadipscing elitr.",
                    verboseHint: NSLocalizedString(
                        "The default of 0.5 for this value keeps autotune ISF closer to pump ISF via a weighted average of fullNewISF and pumpISF. 1.0 allows full adjustment, 0 is no adjustment from pump ISF.",
                        comment: "Autotune ISF Adjustment Fraction"
                    )
                )

                SettingInputSection(
                    decimalValue: $state.min5mCarbimpact,
                    booleanValue: $booleanPlaceholder,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0
                            hintLabel = NSLocalizedString("Min 5m Carbimpact", comment: "Min 5m Carbimpact")
                        }
                    ),
                    units: state.units,
                    type: .decimal("min5mCarbimpact"),
                    label: NSLocalizedString("Min 5m Carbimpact", comment: "Min 5m Carbimpact"),
                    miniHint: "Lorem ipsum dolor sit amet, consetetur sadipscing elitr.",
                    verboseHint: NSLocalizedString(
                        "This is a setting for default carb absorption impact per 5 minutes. The default is an expected 8 mg/dL/5min. This affects how fast COB is decayed in situations when carb absorption is not visible in BG deviations. The default of 8 mg/dL/5min corresponds to a minimum carb absorption rate of 24g/hr at a CSF of 4 mg/dL/g.",
                        comment: "Min 5m Carbimpact"
                    )
                )

                SettingInputSection(
                    decimalValue: $state.remainingCarbsFraction,
                    booleanValue: $booleanPlaceholder,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0
                            hintLabel = NSLocalizedString("Remaining Carbs Fraction", comment: "Remaining Carbs Fraction")
                        }
                    ),
                    units: state.units,
                    type: .decimal("remainingCarbsFraction"),
                    label: NSLocalizedString("Remaining Carbs Fraction", comment: "Remaining Carbs Fraction"),
                    miniHint: "Lorem ipsum dolor sit amet, consetetur sadipscing elitr.",
                    verboseHint: NSLocalizedString(
                        "This is the fraction of carbs we’ll assume will absorb over 4h if we don’t yet see carb absorption.",
                        comment: "Remaining Carbs Fraction"
                    )
                )

                SettingInputSection(
                    decimalValue: $state.remainingCarbsCap,
                    booleanValue: $booleanPlaceholder,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0
                            hintLabel = NSLocalizedString("Remaining Carbs Cap", comment: "Remaining Carbs Cap")
                        }
                    ),
                    units: state.units,
                    type: .decimal("remainingCarbsCap"),
                    label: NSLocalizedString("Remaining Carbs Cap", comment: "Remaining Carbs Cap"),
                    miniHint: "Lorem ipsum dolor sit amet, consetetur sadipscing elitr.",
                    verboseHint: NSLocalizedString(
                        "This is the amount of the maximum number of carbs we’ll assume will absorb over 4h if we don’t yet see carb absorption.",
                        comment: "Remaining Carbs Cap"
                    )
                )

                SettingInputSection(
                    decimalValue: $state.noisyCGMTargetMultiplier,
                    booleanValue: $booleanPlaceholder,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0
                            hintLabel = NSLocalizedString("Noisy CGM Target Multiplier", comment: "Noisy CGM Target Multiplier")
                        }
                    ),
                    units: state.units,
                    type: .decimal("noisyCGMTargetMultiplier"),
                    label: NSLocalizedString("Noisy CGM Target Multiplier", comment: "Noisy CGM Target Multiplier"),
                    miniHint: "Lorem ipsum dolor sit amet, consetetur sadipscing elitr.",
                    verboseHint: NSLocalizedString(
                        "Defaults to 1.3. Increase target by this amount when looping off raw/noisy CGM data",
                        comment: "Noisy CGM Target Multiplier"
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
