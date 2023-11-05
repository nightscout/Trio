import Foundation
import SwiftUI

extension PreferencesEditor {
    final class StateModel: BaseStateModel<Provider>, PreferencesSettable { private(set) var preferences = Preferences()
        @Published var unitsIndex = 1
        @Published var allowAnnouncements = false
        @Published var skipBolusScreenAfterCarbs = false
        @Published var sections: [FieldSection] = []
        @Published var useAlternativeBolusCalc: Bool = false
        @Published var units: GlucoseUnits = .mmolL

        override func subscribe() {
            preferences = provider.preferences
            units = settingsManager.settings.units

            subscribeSetting(\.units, on: $unitsIndex.map { $0 == 0 ? GlucoseUnits.mgdL : .mmolL }) {
                unitsIndex = $0 == .mgdL ? 0 : 1
            } didSet: { [weak self] _ in
                self?.provider.migrateUnits()
            }

            let mainFields = [
                Field(
                    displayName: NSLocalizedString("Max IOB", comment: "Max IOB"),
                    type: .decimal(keypath: \.maxIOB),
                    infoText: NSLocalizedString(
                        "Max IOB is the maximum amount of insulin on board from all sources – both basal (or SMB correction) and bolus insulin – that your loop is allowed to accumulate to treat higher-than-target BG. Unlike the other two OpenAPS safety settings (max_daily_safety_multiplier and current_basal_safety_multiplier), max_iob is set as a fixed number of units of insulin. As of now manual boluses are NOT limited by this setting. \n\n To test your basal rates during nighttime, you can modify the Max IOB setting to zero while in Closed Loop. This will enable low glucose suspend mode while testing your basal rates settings\n\n(Tip from https://www.loopandlearn.org/freeaps-x/#open-loop).",
                        comment: "Max IOB"
                    ),
                    settable: self
                ),
                Field(
                    displayName: NSLocalizedString("Max COB", comment: "Max COB"),
                    type: .decimal(keypath: \.maxCOB),
                    infoText: NSLocalizedString(
                        "The default of maxCOB is 120. (If someone enters more carbs in one or multiple entries, iAPS will cap COB to maxCOB and keep it at maxCOB until the carbs entered above maxCOB have shown to be absorbed. Essentially, this just limits UAM as a safety cap against weird COB calculations due to fluky data.)",
                        comment: "Max COB"
                    ),
                    settable: self
                ),
                Field(
                    displayName: NSLocalizedString("Max Daily Safety Multiplier", comment: "Max Daily Safety Multiplier"),
                    type: .decimal(keypath: \.maxDailySafetyMultiplier),
                    infoText: NSLocalizedString(
                        "This is an important OpenAPS safety limit. The default setting (which is unlikely to need adjusting) is 3. This means that OpenAPS will never be allowed to set a temporary basal rate that is more than 3x the highest hourly basal rate programmed in a user’s pump, or, if enabled, determined by autotune.",
                        comment: "Max Daily Safety Multiplier"
                    ),
                    settable: self
                ),
                Field(
                    displayName: NSLocalizedString("Current Basal Safety Multiplier", comment: "Current Basal Safety Multiplier"),
                    type: .decimal(keypath: \.currentBasalSafetyMultiplier),
                    infoText: NSLocalizedString(
                        "This is another important OpenAPS safety limit. The default setting (which is also unlikely to need adjusting) is 4. This means that OpenAPS will never be allowed to set a temporary basal rate that is more than 4x the current hourly basal rate programmed in a user’s pump, or, if enabled, determined by autotune.",
                        comment: "Current Basal Safety Multiplier"
                    ),
                    settable: self
                ),

                Field(
                    displayName: NSLocalizedString("Autosens Max", comment: "Autosens Max"),
                    type: .decimal(keypath: \.autosensMax),
                    infoText: NSLocalizedString(
                        "This is a multiplier cap for autosens (and autotune) to set a 20% max limit on how high the autosens ratio can be, which in turn determines how high autosens can adjust basals, how low it can adjust ISF, and how low it can set the BG target.",
                        comment: "Autosens Max"
                    ),
                    settable: self
                ),
                Field(
                    displayName: NSLocalizedString("Autosens Min", comment: "Autosens Min"),
                    type: .decimal(keypath: \.autosensMin),
                    infoText: NSLocalizedString(
                        "The other side of the autosens safety limits, putting a cap on how low autosens can adjust basals, and how high it can adjust ISF and BG targets.",
                        comment: "Autosens Min"
                    ),
                    settable: self
                )
            ]

            let smbFields = [
                Field(
                    displayName: NSLocalizedString("Enable SMB Always", comment: "Enable SMB Always"),
                    type: .boolean(keypath: \.enableSMBAlways),
                    infoText: NSLocalizedString(
                        "Defaults to false. When true, always enable supermicrobolus (unless disabled by high temptarget).",
                        comment: "Enable SMB Always"
                    ),
                    settable: self
                ),
                Field(
                    displayName: NSLocalizedString("Max Delta-BG Threshold SMB", comment: "Max Delta-BG Threshold"),
                    type: .decimal(keypath: \.maxDeltaBGthreshold),
                    infoText: NSLocalizedString(
                        "Defaults to 0.2 (20%). Maximum positive percentual change of BG level to use SMB, above that will disable SMB. Hardcoded cap of 40%. For UAM fully-closed-loop 30% is advisable. Observe in log and popup (maxDelta 27 > 20% of BG 100 - disabling SMB!).",
                        comment: "Max Delta-BG Threshold"
                    ),
                    settable: self
                ),
                Field(
                    displayName: NSLocalizedString("Enable SMB With COB", comment: "Enable SMB With COB"),
                    type: .boolean(keypath: \.enableSMBWithCOB),
                    infoText: NSLocalizedString(
                        "This enables supermicrobolus (SMB) while carbs on board (COB) are positive.",
                        comment: "Enable SMB With COB"
                    ),
                    settable: self
                ),
                Field(
                    displayName: NSLocalizedString("Enable SMB With Temptarget", comment: "Enable SMB With Temptarget"),
                    type: .boolean(keypath: \.enableSMBWithTemptarget),
                    infoText: NSLocalizedString(
                        "This enables supermicrobolus (SMB) with eating soon / low temp targets. With this feature enabled, any temporary target below 100mg/dL, such as a temp target of 99 (or 80, the typical eating soon target) will enable SMB.",
                        comment: "Enable SMB With Temptarget"
                    ),
                    settable: self
                ),
                Field(
                    displayName: NSLocalizedString("Enable SMB After Carbs", comment: "Enable SMB After Carbs"),
                    type: .boolean(keypath: \.enableSMBAfterCarbs),
                    infoText: NSLocalizedString(
                        "Defaults to false. When true, enables supermicrobolus (SMB) for 6h after carbs, even with 0 carbs on board (COB).",
                        comment: "Enable SMB After Carbs"
                    ),
                    settable: self
                ),
                Field(
                    displayName: NSLocalizedString(
                        "Allow SMB With High Temptarget",
                        comment: "Allow SMB With High Temptarget"
                    ),
                    type: .boolean(keypath: \.allowSMBWithHighTemptarget),
                    infoText: NSLocalizedString(
                        "Defaults to false. When true, allows supermicrobolus (if otherwise enabled) even with high temp targets (> 100 mg/dl).",
                        comment: "Allow SMB With High Temptarget"
                    ),
                    settable: self
                ),
                Field(
                    displayName: NSLocalizedString("Enable SMB With High BG", comment: "Enable SMB With High BG"),
                    type: .boolean(keypath: \.enableSMB_high_bg),
                    infoText: NSLocalizedString(
                        "Enable SMBs when a high BG is detected, based on the high BG target (adjusted or profile)",
                        comment: "Enable SMB With High BG"
                    ),
                    settable: self
                ),
                Field(
                    displayName: NSLocalizedString(
                        "... When Blood Glucose Is Over (mg/dl):",
                        comment: "... When Blood Glucose Is Over (mg/dl):"
                    ),
                    type: .decimal(keypath: \.enableSMB_high_bg_target),
                    infoText: NSLocalizedString(
                        "Set the value enableSMB_high_bg will compare against to enable SMB. If BG > than this value, SMBs should enable.",
                        comment: "... When Blood Glucose Is Over (mg/dl):"
                    ),
                    settable: self
                ),
                Field(
                    displayName: NSLocalizedString("Enable UAM", comment: "Enable UAM"),
                    type: .boolean(keypath: \.enableUAM),
                    infoText: NSLocalizedString(
                        "With this option enabled, the SMB algorithm can recognize unannounced meals. This is helpful, if you forget to tell iAPS about your carbs or estimate your carbs wrong and the amount of entered carbs is wrong or if a meal with lots of fat and protein has a longer duration than expected. Without any carb entry, UAM can recognize fast glucose increasments caused by carbs, adrenaline, etc, and tries to adjust it with SMBs. This also works the opposite way: if there is a fast glucose decreasement, it can stop SMBs earlier.",
                        comment: "Enable UAM"
                    ),
                    settable: self
                ),
                Field(
                    displayName: NSLocalizedString("Max SMB Basal Minutes", comment: "Max SMB Basal Minutes"),
                    type: .decimal(keypath: \.maxSMBBasalMinutes),
                    infoText: NSLocalizedString(
                        "Defaults to start at 30. This is the maximum minutes of basal that can be delivered as a single SMB with uncovered COB. This gives the ability to make SMB more aggressive if you choose. It is recommended that the value is set to start at 30, in line with the default, and if you choose to increase this value, do so in no more than 15 minute increments, keeping a close eye on the effects of the changes. It is not recommended to set this value higher than 90 mins, as this may affect the ability for the algorithm to safely zero temp. It is also recommended that pushover is used when setting the value to be greater than default, so that alerts are generated for any predicted lows or highs.",
                        comment: "Max SMB Basal Minutes"
                    ),
                    settable: self
                ),
                Field(
                    displayName: NSLocalizedString("Max UAM SMB Basal Minutes", comment: "Max UAM SMB Basal Minutes"),
                    type: .decimal(keypath: \.maxUAMSMBBasalMinutes),
                    infoText: NSLocalizedString(
                        "Defaults to start at 30. This is the maximum minutes of basal that can be delivered by UAM as a single SMB when IOB exceeds COB. This gives the ability to make UAM more or less aggressive if you choose. It is recommended that the value is set to start at 30, in line with the default, and if you choose to increase this value, do so in no more than 15 minute increments, keeping a close eye on the effects of the changes. Reducing the value will cause UAM to dose less insulin for each SMB. It is not recommended to set this value higher than 60 mins, as this may affect the ability for the algorithm to safely zero temp. It is also recommended that pushover is used when setting the value to be greater than default, so that alerts are generated for any predicted lows or highs.",
                        comment: "Max UAM SMB Basal Minutes"
                    ),
                    settable: self
                ),
                Field(
                    displayName: NSLocalizedString("SMB DeliveryRatio", comment: "SMB DeliveryRatio"),
                    type: .decimal(keypath: \.smbDeliveryRatio),
                    infoText: NSLocalizedString(
                        "Default value: 0.5 This is another key OpenAPS safety cap, and specifies what share of the total insulin required can be delivered as SMB. Increase this experimental value slowly and with caution.",
                        comment: "SMB DeliveryRatio"
                    ),
                    settable: self
                ),
                Field(
                    displayName: NSLocalizedString("SMB Interval", comment: "SMB Interval"),
                    type: .decimal(keypath: \.smbInterval),
                    infoText: NSLocalizedString(
                        "Minimum duration in minutes for new SMB since last SMB or manual bolus",
                        comment: "SMB Interval"
                    ),
                    settable: self
                ),
                Field(
                    displayName: NSLocalizedString("Bolus Increment", comment: "Bolus Increment"),
                    type: .decimal(keypath: \.bolusIncrement),
                    infoText: NSLocalizedString(
                        "Smallest enacted SMB amount. Minimum amount for Omnipod pumps is 0.05 U, whereas for Medtronic pumps it differs for various models, from 0.025 U to 0.10 U. Please check the minimum bolus amount which can be delivered by your pump. The default value is 0.1.",
                        comment: "Bolus Increment"
                    ),
                    settable: self
                )
            ]

            // MARK: - Targets fields

            let targetSettings = [
                Field(
                    displayName: NSLocalizedString(
                        "High Temptarget Raises Sensitivity",
                        comment: "High Temptarget Raises Sensitivity"
                    ),
                    type: .boolean(keypath: \.highTemptargetRaisesSensitivity),
                    infoText: NSLocalizedString(
                        "Defaults to false. When set to true, raises sensitivity (lower sensitivity ratio) for temp targets set to >= 111. Synonym for exercise_mode. The higher your temp target above 110 will result in more sensitive (lower) ratios, e.g., temp target of 120 results in sensitivity ratio of 0.75, while 140 results in 0.6 (with default halfBasalTarget of 160).",
                        comment: "High Temptarget Raises Sensitivity"
                    ),
                    settable: self
                ),
                Field(
                    displayName: NSLocalizedString(
                        "Low Temptarget Lowers Sensitivity",
                        comment: "Low Temptarget Lowers Sensitivity"
                    ),
                    type: .boolean(keypath: \.lowTemptargetLowersSensitivity),
                    infoText: NSLocalizedString(
                        "Defaults to false. When set to true, can lower sensitivity (higher sensitivity ratio) for temptargets <= 99. The lower your temp target below 100 will result in less sensitive (higher) ratios, e.g., temp target of 95 results in sensitivity ratio of 1.09, while 85 results in 1.33 (with default halfBasalTarget of 160).",
                        comment: "Low Temptarget Lowers Sensitivity"
                    ),
                    settable: self
                ),
                Field(
                    displayName: NSLocalizedString("Sensitivity Raises Target", comment: "Sensitivity Raises Target"),
                    type: .boolean(keypath: \.sensitivityRaisesTarget),
                    infoText: NSLocalizedString(
                        "When true, raises BG target when autosens detects sensitivity",
                        comment: "Sensitivity Raises Target"
                    ),
                    settable: self
                ),
                Field(
                    displayName: NSLocalizedString("Resistance Lowers Target", comment: "Resistance Lowers Target"),
                    type: .boolean(keypath: \.resistanceLowersTarget),
                    infoText: NSLocalizedString(
                        "Defaults to false. When true, will lower BG target when autosens detects resistance",
                        comment: "Resistance Lowers Target"
                    ),
                    settable: self
                ),
                Field(
                    displayName: NSLocalizedString("Half Basal Exercise Target", comment: "Half Basal Exercise Target"),
                    type: .decimal(keypath: \.halfBasalExerciseTarget),
                    infoText: NSLocalizedString(
                        "Set to a number, e.g. 160, which means when temp target is 160 mg/dL, run 50% basal at this level (120 = 75%; 140 = 60%). This can be adjusted, to give you more control over your exercise modes.",
                        comment: "Half Basal Exercise Target"
                    ),
                    settable: self
                )
            ]

            // MARK: - Other fields

            let otherSettings = [
                Field(
                    displayName: NSLocalizedString("Rewind Resets Autosens", comment: "Rewind Resets Autosens"),
                    type: .boolean(keypath: \.rewindResetsAutosens),
                    infoText: NSLocalizedString(
                        "This feature, enabled by default, resets the autosens ratio to neutral when you rewind your pump, on the assumption that this corresponds to a probable site change. Autosens will begin learning sensitivity anew from the time of the rewind, which may take up to 6 hours. If you usually rewind your pump independently of site changes, you may want to consider disabling this feature.",
                        comment: "Rewind Resets Autosens"
                    ),
                    settable: self
                ),
                Field(
                    displayName: NSLocalizedString("Use Custom Peak Time", comment: "Use Custom Peak Time"),
                    type: .boolean(keypath: \.useCustomPeakTime),
                    infoText: NSLocalizedString(
                        "Defaults to false. Setting to true allows changing insulinPeakTime", comment: "Use Custom Peak Time"
                    ),
                    settable: self
                ),
                Field(
                    displayName: NSLocalizedString("Insulin Peak Time", comment: "Insulin Peak Time"),
                    type: .decimal(keypath: \.insulinPeakTime),
                    infoText: NSLocalizedString(
                        "Time of maximum blood glucose lowering effect of insulin, in minutes. Beware: Oref assumes for ultra-rapid (Lyumjev) & rapid-acting (Fiasp) curves minimal (35 & 50 min) and maximal (100 & 120 min) applicable insulinPeakTimes. Using a custom insulinPeakTime outside these bounds will result in issues with iAPS, longer loop calculations and possible red loops.",
                        comment: "Insulin Peak Time"
                    ),
                    settable: self
                ),
                Field(
                    displayName: NSLocalizedString("Skip Neutral Temps", comment: "Skip Neutral Temps"),
                    type: .boolean(keypath: \.skipNeutralTemps),
                    infoText: NSLocalizedString(
                        "Defaults to false, so that iAPS will set temps whenever it can, so it will be easier to see if the system is working, even when you are offline. This means iAPS will set a “neutral” temp (same as your default basal) if no adjustments are needed. This is an old setting for OpenAPS to have the options to minimise sounds and notifications from the 'rig', that may wake you up during the night.",
                        comment: "Skip Neutral Temps"
                    ),
                    settable: self
                ),
                Field(
                    displayName: NSLocalizedString("Unsuspend If No Temp", comment: "Unsuspend If No Temp"),
                    type: .boolean(keypath: \.unsuspendIfNoTemp),
                    infoText: NSLocalizedString(
                        "Many people occasionally forget to resume / unsuspend their pump after reconnecting it. If you’re one of them, and you are willing to reliably set a zero temp basal whenever suspending and disconnecting your pump, this feature has your back. If enabled, it will automatically resume / unsuspend the pump if you forget to do so before your zero temp expires. As long as the zero temp is still running, it will leave the pump suspended.",
                        comment: "Unsuspend If No Temp"
                    ),
                    settable: self
                ),
                Field(
                    displayName: NSLocalizedString("Suspend Zeros IOB", comment: "Suspend Zeros IOB"),
                    type: .boolean(keypath: \.suspendZerosIOB),
                    infoText: NSLocalizedString(
                        "Default is false. Any existing temp basals during times the pump was suspended will be deleted and 0 temp basals to negate the profile basal rates during times pump is suspended will be added.",
                        comment: "Suspend Zeros IOB"
                    ),
                    settable: self
                ),
                Field(
                    displayName: NSLocalizedString("Min 5m Carbimpact", comment: "Min 5m Carbimpact"),
                    type: .decimal(keypath: \.min5mCarbimpact),
                    infoText: NSLocalizedString(
                        "This is a setting for default carb absorption impact per 5 minutes. The default is an expected 8 mg/dL/5min. This affects how fast COB is decayed in situations when carb absorption is not visible in BG deviations. The default of 8 mg/dL/5min corresponds to a minimum carb absorption rate of 24g/hr at a CSF of 4 mg/dL/g.",
                        comment: "Min 5m Carbimpact"
                    ),
                    settable: self
                ),
                Field(
                    displayName: NSLocalizedString(
                        "Autotune ISF Adjustment Fraction",
                        comment: "Autotune ISF Adjustment Fraction"
                    ),
                    type: .decimal(keypath: \.autotuneISFAdjustmentFraction),
                    infoText: NSLocalizedString(
                        "The default of 0.5 for this value keeps autotune ISF closer to pump ISF via a weighted average of fullNewISF and pumpISF. 1.0 allows full adjustment, 0 is no adjustment from pump ISF.",
                        comment: "Autotune ISF Adjustment Fraction"
                    ),
                    settable: self
                ),
                Field(
                    displayName: NSLocalizedString("Remaining Carbs Fraction", comment: "Remaining Carbs Fraction"),
                    type: .decimal(keypath: \.remainingCarbsFraction),
                    infoText: NSLocalizedString(
                        "This is the fraction of carbs we’ll assume will absorb over 4h if we don’t yet see carb absorption.",
                        comment: "Remaining Carbs Fraction"
                    ),
                    settable: self
                ),
                Field(
                    displayName: NSLocalizedString("Remaining Carbs Cap", comment: "Remaining Carbs Cap"),
                    type: .decimal(keypath: \.remainingCarbsCap),
                    infoText: NSLocalizedString(
                        "This is the amount of the maximum number of carbs we’ll assume will absorb over 4h if we don’t yet see carb absorption.",
                        comment: "Remaining Carbs Cap"
                    ),
                    settable: self
                ),
                Field(
                    displayName: NSLocalizedString("Noisy CGM Target Multiplier", comment: "Noisy CGM Target Multiplier"),
                    type: .decimal(keypath: \.noisyCGMTargetMultiplier),
                    infoText: NSLocalizedString(
                        "Defaults to 1.3. Increase target by this amount when looping off raw/noisy CGM data",
                        comment: "Noisy CGM Target Multiplier"
                    ),
                    settable: self
                )
            ]

            sections = [
                FieldSection(
                    displayName: NSLocalizedString("OpenAPS main settings", comment: "OpenAPS main settings"), fields: mainFields
                ),
                FieldSection(
                    displayName: NSLocalizedString("OpenAPS SMB settings", comment: "OpenAPS SMB settings"),
                    fields: smbFields
                ),
                FieldSection(
                    displayName: NSLocalizedString("OpenAPS targets settings", comment: "OpenAPS targets settings"),
                    fields: targetSettings
                ),
                FieldSection(
                    displayName: NSLocalizedString("OpenAPS other settings", comment: "OpenAPS other settings"),
                    fields: otherSettings
                )
            ]
        }

        func set<T>(_ keypath: WritableKeyPath<Preferences, T>, value: T) {
            preferences[keyPath: keypath] = value
            save()
        }

        func get<T>(_ keypath: WritableKeyPath<Preferences, T>) -> T {
            preferences[keyPath: keypath]
        }

        func save() {
            provider.savePreferences(preferences)
        }
    }
}
