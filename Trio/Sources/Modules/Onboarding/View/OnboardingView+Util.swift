import SwiftUI

/// Represents the navigation direction in the onboarding flow
enum OnboardingNavigationDirection {
    case forward
    case backward
}

/// Represents the different steps in the onboarding process.
enum OnboardingStep: Int, CaseIterable, Identifiable, Equatable {
    case welcome
    case startupGuide
    case overview
    case diagnostics
    case nightscout
    case unitSelection
    case glucoseTarget
    case basalRates
    case carbRatio
    case insulinSensitivity
    case deliveryLimits
    case algorithmSettings
//    case autosensSettings
//    case smbSettings
//    case targetBehavior
    case completed

    var id: Int { rawValue }

    var hasSubsteps: Bool {
        self == .deliveryLimits
    }

    var substeps: [DeliveryLimitSubstep] {
        guard hasSubsteps else { return [] }
        return DeliveryLimitSubstep.allCases
    }

    /// The title to display for this onboarding step.
    var title: String {
        switch self {
        case .welcome:
            return String(localized: "Welcome to Trio")
        case .startupGuide:
            return String(localized: "Startup Guide")
        case .overview:
            return String(localized: "Overview")
        case .diagnostics:
            return String(localized: "Diagnostics")
        case .nightscout:
            return String(localized: "Nightscout")
        case .unitSelection:
            return String(localized: "Units & Pump")
        case .glucoseTarget:
            return String(localized: "Glucose Targets")
        case .basalRates:
            return String(localized: "Basal Rates")
        case .carbRatio:
            return String(localized: "Carb Ratios")
        case .insulinSensitivity:
            return String(localized: "Insulin Sensitivities")
        case .deliveryLimits:
            return String(localized: "Delivery Limits")
        case .algorithmSettings:
            return String(localized: "Algorithm Settings")
//        case .autosensSettings:
//            return String(localized: "Autosens")
//        case .smbSettings:
//            return String(localized: "Super Micro Bolus (SMB)")
//        case .targetBehavior:
//            return String(localized: "Target Behavior")
        case .completed:
            return String(localized: "All Set!")
        }
    }

    /// A detailed description of what this onboarding step is about.
    var description: String {
        switch self {
        case .welcome:
            return String(
                localized: "Trio is a powerful app that helps you manage your diabetes. Let's get started by setting up a few important parameters that will help Trio work effectively for you."
            )
        case .startupGuide:
            return String(
                localized: "Trio comes with a helpful Startup Guide. We recommend opening it now and following along as you go — side by side."
            )
        case .overview:
            return String(
                localized: "Trio's Onboarding consists of several steps. It takes about 5-10 minutes to complete. We'll guide you through each step."
            )
        case .diagnostics:
            return String(
                localized: "By default, Trio collects crash reports and other anonymized data related to errors, exceptions, and overall app performance."
            )
        case .nightscout:
            return String(
                localized: "Nightscout is a cloud-based platform that allows you to store your diabetes data. It's often used by caregivers to remotely monitor what Trio is doing."
            )
        case .unitSelection:
            return String(
                localized: "Before you can begin with configuring your therapy settigns, Trio needs to know which units you use for your glucose and insulin measurements (based on your pump model)."
            )
        case .glucoseTarget:
            return String(
                localized: "Your glucose target is the blood glucose level you aim to maintain. Trio will use this to calculate insulin doses and provide recommendations."
            )
        case .basalRates:
            return String(
                localized: "Your basal profile represents the amount of background insulin you need throughout the day. This helps Trio calculate your insulin needs."
            )
        case .carbRatio:
            return String(
                localized: "Your carb ratio tells how many grams of carbohydrates one unit of insulin will cover. This is essential for accurate meal bolus calculations."
            )
        case .insulinSensitivity:
            return String(
                localized: "Your insulin sensitivity factor (ISF) indicates how much one unit of insulin will lower your blood glucose. This helps calculate correction boluses."
            )
        case .deliveryLimits:
            return String(
                localized: "Trio includes several safety limits for insulin delivery and carbohydrate entry, helping ensure a safe and effective experience."
            )
        case .algorithmSettings:
            return String(
                localized: "Trio includes several algorithm settings that allow you to customize the oref algorithm behavior to suit your specific needs."
            )
//        case .autosensSettings:
//            return String(
//                localized: "Auto-sensitivity (Autosens) adjusts insulin delivery based on observed sensitivity or resistance."
//            )
//        case .smbSettings:
//            return String(
//                localized: "SMB (Super Micro Bolus) is an oref algorithm feature that delivers small frequent boluses instead of temporary basals for faster glucose control."
//            )
//        case .targetBehavior:
//            return String(
//                localized: "Target Behavior allows you to adjust how temporary targets influence ISF, basal, and auto-targeting based on sensitivity or resistance."
//            )
        case .completed:
            return String(
                localized: "Great job! You've completed the initial setup of Trio. You can always adjust these settings later in the app."
            )
        }
    }

    /// The system icon name associated with this step.
    var iconName: String {
        switch self {
        case .welcome:
            return "hand.wave.fill"
        case .startupGuide:
            return "list.bullet.clipboard.fill"
        case .algorithmSettings,
             .overview:
            return "checklist.unchecked"
        case .diagnostics:
            return "waveform.badge.magnifyingglass"
        case .nightscout:
            return "owl"
        case .unitSelection:
            return "numbers.rectangle"
        case .glucoseTarget:
            return "target"
        case .basalRates:
            return "chart.xyaxis.line"
        case .carbRatio:
            return "fork.knife"
        case .insulinSensitivity:
            return "drop.fill"
        case .deliveryLimits:
            return "slider.horizontal.3"
//        case .autosensSettings,
//             .deliveryLimits,
//             .smbSettings,
//             .targetBehavior:
//            return "slider.horizontal.3"
        case .completed:
            return "checkmark.circle.fill"
        }
    }

    /// Returns the next step in the onboarding process, or nil if this is the last step.
    var next: OnboardingStep? {
        let allCases = OnboardingStep.allCases
        let currentIndex = allCases.firstIndex(of: self) ?? 0
        let nextIndex = currentIndex + 1
        return nextIndex < allCases.count ? allCases[nextIndex] : nil
    }

    /// Returns the previous step in the onboarding process, or nil if this is the first step.
    var previous: OnboardingStep? {
        let allCases = OnboardingStep.allCases
        let currentIndex = allCases.firstIndex(of: self) ?? 0
        let previousIndex = currentIndex - 1
        return previousIndex >= 0 ? allCases[previousIndex] : nil
    }

    /// The accent color to use for this step.
    var accentColor: Color {
        switch self {
        case .algorithmSettings,
//             .autosensSettings,
             .completed,
             .deliveryLimits,
             .diagnostics,
             .nightscout,
             .overview,
//             .smbSettings,
             .startupGuide,
//             .targetBehavior,
             .unitSelection,
             .welcome:
            return Color.blue
        case .glucoseTarget:
            return Color.green
        case .basalRates:
            return Color.purple
        case .carbRatio:
            return Color.orange
        case .insulinSensitivity:
            return Color.red
        }
    }
}

var nonInfoOnboardingSteps: [OnboardingStep] { OnboardingStep.allCases
    .filter { $0 != .welcome && $0 != .startupGuide && $0 != .overview && $0 != .completed }
}

enum DeliveryLimitSubstep: Int, CaseIterable, Identifiable {
    case maxIOB
    case maxBolus
    case maxBasal
    case maxCOB
    case minimumSafetyThreshold

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .maxIOB: return String(localized: "Max IOB", comment: "Max IOB")
        case .maxBolus: return String(localized: "Max Bolus")
        case .maxBasal: return String(localized: "Max Basal Rate")
        case .maxCOB: return String(localized: "Max COB", comment: "Max COB")
        case .minimumSafetyThreshold: return String(localized: "Minimum Safety Threshold")
        }
    }

    var hint: String {
        switch self {
        case .maxIOB: return String(localized: "Maximum units of insulin allowed to be active.")
        case .maxBolus: return String(localized: "Largest bolus of insulin allowed.")
        case .maxBasal: return String(localized: "Largest basal rate allowed.")
        case .maxCOB: return String(localized: "Maximum Carbs On Board (COB) allowed.")
        case .minimumSafetyThreshold: return String(localized: "Increase the safety threshold used to suspend insulin delivery.")
        }
    }

    func description(units: GlucoseUnits) -> any View {
        switch self {
        case .maxIOB:
            return VStack(alignment: .leading, spacing: 8) {
                Text(
                    "Note: This setting must be greater than 0 for any automatic insulin dosing by Trio."
                ).bold().foregroundStyle(Color.primary)

                Text(
                    "This is the maximum amount of Insulin On Board (IOB) above profile basal rates from all sources - positive temporary basal rates, manual or meal boluses, and SMBs - that Trio is allowed to accumulate to address an above target glucose."
                )
                Text(
                    "If a calculated amount exceeds this limit, the suggested and / or delivered amount will be reduced so that active insulin on board (IOB) will not exceed this safety limit."
                )
                Text(
                    "Note: You can still manually bolus above this limit, but the suggested bolus amount will never exceed this in the bolus calculator."
                )
            }
        case .maxBolus:
            return VStack(alignment: .leading, spacing: 8) {
                Text(
                    "This is the maximum bolus allowed to be delivered at one time. This limits manual and automatic bolus."
                )
                Text("Most set this to their largest meal bolus. Then, adjust if needed.")
                Text("If you attempt to request a bolus larger than this, the bolus will not be accepted.")
            }
        case .maxBasal:
            return VStack(alignment: .leading, spacing: 8) {
                Text(
                    "This is the maximum basal rate allowed to be set or scheduled. This applies to both automatic and manual basal rates."
                )
                Text(
                    "Note to Medtronic Pump Users: You must also manually set the max basal rate on the pump to this value or higher."
                )
            }
        case .maxCOB:
            return VStack(alignment: .leading, spacing: 8) {
                Text(
                    "This setting defines the maximum amount of Carbs On Board (COB) at any given time for Trio to use in dosing calculations. If more carbs are entered than allowed by this limit, Trio will cap the current COB in calculations to Max COB and remain at max until all remaining carbs have shown to be absorbed."
                )
                Text(
                    "For example, if Max COB is 120 g and you enter a meal containing 150 g of carbs, your COB will remain at 120 g until the remaining 30 g have been absorbed."
                )
                Text("This is an important limit when UAM is ON.")
            }
        case .minimumSafetyThreshold:
            return VStack(alignment: .leading, spacing: 8) {
                Text("Default: Set by Algorithm").bold()
                Text(
                    "Minimum Threshold Setting is, by default, determined by your set Glucose Target. This threshold automatically suspends insulin delivery if your glucose levels are forecasted to fall below this value. It’s designed to protect against hypoglycemia, particularly during sleep or other vulnerable times."
                )
                Text(
                    "Trio will use the larger of the default setting calculation below and the value entered here."
                )
                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("The default setting is based on this calculation:").bold()
                        Text("TargetGlucose - 0.5 × (TargetGlucose - 40)")
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        Text(
                            "If your glucose target is \(units == .mgdL ? "110" : 110.formattedAsMmolL) \(units.rawValue), Trio will use a safety threshold of \(units == .mgdL ? "75" : 75.formattedAsMmolL) \(units.rawValue), unless you set Minimum Safety Threshold to something > \(units == .mgdL ? "75" : 75.formattedAsMmolL) \(units.rawValue)."
                        )
                        Text(
                            "\(units == .mgdL ? "110" : 110.formattedAsMmolL) - 0.5 × (\(units == .mgdL ? "110" : 110.formattedAsMmolL) - \(units == .mgdL ? "40" : 40.formattedAsMmolL)) = \(units == .mgdL ? "75" : 75.formattedAsMmolL)"
                        )
                    }
                    Text(
                        "This setting is limited to values between \(units == .mgdL ? "60" : 60.formattedAsMmolL) - \(units == .mgdL ? "120" : 120.formattedAsMmolL) \(units.rawValue)"
                    )
                    Text(
                        "Note: Basal may be resumed if there is negative IOB and glucose is rising faster than the forecast."
                    )
                }
            }
        }
    }
}

enum AlgorithmSettingsSubstep: Int, CaseIterable, Identifiable {
    case autosensMin
    case autosensMax
    case rewindResetsAutosens
    case enableSMBAlways
    case enableSMBWithCOB
    case enableSMBWithTempTarget
    case enableSMBAfterCarbs
    case enableSMBWithHighGlucoseTarget
    case allowSMBWithHighTempTarget
    case enableUAM
    case maxSMBMinutes
    case maxUAMMinutes
    case maxDeltaGlucoseThreshold
    case highTempTargetRaisesSensitivity
    case lowTempTargetLowersSensitivity
    case sensitivityRaisesTarget
    case resistanceLowersTarget
    case halfBasalTarget

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .autosensMin: return String(localized: "Autosens Min", comment: "Autosens Min")
        case .autosensMax: return String(localized: "Autosens Max", comment: "Autosens Max")
        case .rewindResetsAutosens: return String(localized: "Rewind Resets Autosens", comment: "Rewind Resets Autosens")
        case .enableSMBAlways: return String(localized: "Enable SMB Always", comment: "Enable SMB Always")
        case .enableSMBWithCOB: return String(localized: "Enable SMB With COB", comment: "Enable SMB With COB")
        case .enableSMBWithTempTarget: return String(
                localized: "Enable SMB With Temptarget",
                comment: "Enable SMB With Temptarget"
            )
        case .enableSMBAfterCarbs: return String(localized: "Enable SMB After Carbs", comment: "Enable SMB After Carbs")
        case .enableSMBWithHighGlucoseTarget: return String(
                localized: "Enable SMB With High BG",
                comment: "Enable SMB With High BG"
            )
        case .allowSMBWithHighTempTarget: return String(
                localized: "Allow SMB With High Temptarget",
                comment: "Allow SMB With High Temptarget"
            )
        case .enableUAM: return String(localized: "Enable UAM", comment: "Enable UAM")
        case .maxSMBMinutes: return String(localized: "Max SMB Basal Minutes", comment: "Max SMB Basal Minutes")
        case .maxUAMMinutes: return String(localized: "Max UAM Basal Minutes", comment: "Max UAM Basal Minutes")
        case .maxDeltaGlucoseThreshold: return String(localized: "Max Delta-BG Threshold SMB", comment: "Max Delta-BG Threshold")
        case .highTempTargetRaisesSensitivity: return String(
                localized: "High Temp Target Raises Sensitivity",
                comment: "High Temp Target Raises Sensitivity"
            )
        case .lowTempTargetLowersSensitivity: return String(
                localized: "High Temp Target Raises Sensitivity",
                comment: "High Temp Target Raises Sensitivity"
            )
        case .sensitivityRaisesTarget: return String(localized: "Sensitivity Raises Target", comment: "Sensitivity Raises Target")
        case .resistanceLowersTarget: return String(localized: "Resistance Lowers Target", comment: "Resistance Lowers Target")
        case .halfBasalTarget: return String(localized: "Half Basal Exercise Target", comment: "Half Basal Exercise Target")
        }
    }

    func hint(units: GlucoseUnits) -> String {
        switch self {
        case .autosensMin: return String(localized: "Lower limit of the Autosens Ratio.")
        case .autosensMax: return String(localized: "Upper limit of the Autosens Ratio.")
        case .rewindResetsAutosens: return String(localized: "Pump rewind initiates a reset in Autosens Ratio.")
        case .enableSMBAlways: return String(localized: "Allow SMBs at all times except when a high Temp Target is set.")
        case .enableSMBWithCOB: return String(localized: "Allow SMB when carbs are on board.")
        case .enableSMBWithTempTarget: return String(
                localized: "Allow SMB when a manual Temporary Target is set under \(units == .mgdL ? "100" : 100.formattedAsMmolL) \(units.rawValue)."
            )
        case .enableSMBAfterCarbs: return String(localized: "Allow SMB for 6 hrs after a carb entry.")
        case .enableSMBWithHighGlucoseTarget: return String(localized: "Allow SMB when glucose is above the High BG Target value.")
        case .allowSMBWithHighTempTarget: return String(
                localized: "Allow SMB when a manual Temporary Target is set greater than \(units == .mgdL ? "100" : 100.formattedAsMmolL) \(units.rawValue)."
            )
        case .enableUAM: return String(localized: "Enable Unannounced Meals SMB.")
        case .maxSMBMinutes: return String(localized: "Limits the size of a single Super Micro Bolus (SMB) dose.")
        case .maxUAMMinutes: return String(localized: "Limits the size of a single Unannounced Meal (UAM) SMB dose.")
        case .maxDeltaGlucoseThreshold: return String(localized: "Disables SMBs if last two glucose values differ by more than this percent.")
        case .highTempTargetRaisesSensitivity: return String(
                localized: "Increase sensitivity when glucose is above target if a manual Temp Target > \(units == .mgdL ? "100" : 100.formattedAsMmolL) \(units.rawValue) is set."
            )
        case .lowTempTargetLowersSensitivity: return String(
                localized: "Decrease sensitivity when glucose is below target if a manual Temp Target < \(units == .mgdL ? "100" : 100.formattedAsMmolL) \(units.rawValue) is set."
            )
        case .sensitivityRaisesTarget: return String(localized: "Raise target glucose if when Autosens Ratio is >1.")
        case .resistanceLowersTarget: return String(localized: "Lower target glucose when Autosens Ratio is <1.")
        case .halfBasalTarget: return String(localized: "Scales down your basal rate to 50% at this value.")
        }
    }

    func description(units: GlucoseUnits) -> any View {
        switch self {
        case .autosensMin:
            return VStack(alignment: .leading, spacing: 8) {
                Text("Default: 70%").bold()
                Text(
                    "Autosens Min sets the minimum Autosens Ratio used by Autosens, Dynamic ISF, and Sigmoid Formula."
                )
                Text(
                    "The Autosens Ratio is used to calculate the amount of adjustment needed to basal rates, ISF, and CR."
                )
                Text(
                    "Tip: Decreasing this value allows automatic adjustments of basal rates to be lower, ISF to be higher, and CR to be higher."
                )
            }
        case .autosensMax:
            return VStack(alignment: .leading, spacing: 8) {
                Text("Default: 120%").bold()
                Text(
                    "Autosens Max sets the maximum Autosens Ratio used by Autosens, Dynamic ISF, and Sigmoid Formula."
                )
                Text(
                    "The Autosens Ratio is used to calculate the amount of adjustment needed to basal rates, ISF, and CR."
                )
                Text(
                    "Tip: Increasing this value allows automatic adjustments of basal rates to be higher, ISF to be lower, and CR to be lower."
                )
            }
        case .rewindResetsAutosens:
            return VStack(alignment: .leading, spacing: 8) {
                Text(
                    "This feature resets the Autosens Ratio to neutral when you rewind your pump on the assumption that this corresponds to a site change."
                )
                Text(
                    "Autosens will begin learning sensitivity anew from the time of the rewind, which may take up to 6 hours."
                )
                Text(
                    "Tip: If you usually rewind your pump independently of site changes, you may want to consider disabling this feature."
                )
            }
        case .enableSMBAlways:
            return VStack(alignment: .leading, spacing: 8) {
                Text("Default: OFF").bold()
                Text(
                    "When enabled, Super Micro Boluses (SMBs) will always be allowed if dosing calculations determine insulin is needed via the SMB delivery method, except when a high Temp Target is set. Enabling SMB Always will remove redundant \"Enable SMB\" options when this setting is enacted."
                )
                Text(
                    "Note: If you would like to allow SMBs when a high Temp Target is set, enable the \"Allow SMBs with High Temptarget\" setting."
                )
            }
        case .enableSMBWithCOB:
            return VStack(alignment: .leading, spacing: 8) {
                Text("Default: OFF").bold()
                Text(
                    "When the carb on board (COB) forecast line is active, enabling this feature allows Trio to use Super Micro Boluses (SMB) to deliver the insulin required."
                )
                Text(
                    "Note: If this is enabled and the criteria are met, SMBs could be utilized regardless of other SMB settings being enabled or not."
                )
            }
        case .enableSMBWithTempTarget:
            return VStack(alignment: .leading, spacing: 8) {
                Text("Default: OFF").bold()
                Text(
                    "Enabling this feature allows Trio to deliver insulin required using Super Micro Boluses (SMB) at times when a manual Temporary Target under \(units == .mgdL ? "100" : 100.formattedAsMmolL) \(units.rawValue) is set."
                )
                Text(
                    "Note: If this is enabled and the criteria are met, SMBs could be utilized regardless of other SMB settings being enabled or not."
                )
            }
        case .enableSMBAfterCarbs:
            return VStack(alignment: .leading, spacing: 8) {
                Text("Default: OFF").bold()
                Text(
                    "Enabling this feature allows Trio to deliver insulin required using Super Micro Boluses (SMB) for 6 hours after a carb entry, regardless of whether there are active carbs on board (COB)."
                )
                Text(
                    "Note: If this is enabled and the criteria are met, SMBs could be utilized regardless of other SMB settings being enabled or not."
                )
            }
        case .enableSMBWithHighGlucoseTarget:
            return VStack(alignment: .leading, spacing: 8) {
                Text("Default: OFF").bold()
                Text(
                    "Enabling this feature allows Trio to deliver insulin required using Super Micro Boluses (SMB) when glucose reading is above the value set as High BG Target."
                )
                Text(
                    "Note: If this is enabled and the criteria are met, SMBs could be utilized regardless of other SMB settings being enabled or not."
                )
            }
        case .allowSMBWithHighTempTarget:
            return VStack(alignment: .leading, spacing: 8) {
                Text("Default: OFF").bold()
                Text(
                    "Enabling this feature allows Trio to deliver insulin required using Super Micro Boluses (SMB) when a manual Temporary Target above \(units == .mgdL ? "100" : 100.formattedAsMmolL) \(units.rawValue) is set."
                )
                Text(
                    "Note: If this is enabled and the criteria are met, SMBs could be utilized regardless of other SMB settings being enabled or not."
                )
                Text(
                    "Warning: High Temp Targets are often set when recovering from lows. If you use High Temp Targets for that purpose, this feature should remain disabled."
                ).bold()
            }
        case .enableUAM:
            return VStack(alignment: .leading, spacing: 8) {
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
        case .maxSMBMinutes:
            return VStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Default: 30 minutes").bold()
                        Text("(50% current basal rate)").bold()
                    }
                    VStack(alignment: .leading, spacing: 8) {
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

                VStack(alignment: .leading, spacing: 8) {
                    Text(
                        "Warning: Increasing this value above 90 minutes may impact Trio's ability to effectively zero temp and prevent lows."
                    ).bold()
                    Text("Note: SMBs must be enabled to use this limit.")
                }
            }
        case .maxUAMMinutes:
            return VStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Default: 30 minutes").bold()
                        Text("(50% current basal rate)").bold()
                    }
                    VStack(alignment: .leading, spacing: 8) {
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
                VStack(alignment: .leading, spacing: 8) {
                    Text(
                        "Warning: Increasing this value above 60 minutes may impact Trio's ability to effectively zero temp and prevent lows."
                    ).bold()
                    Text("Note: UAM SMBs must be enabled to use this limit.")
                }
            }
        case .maxDeltaGlucoseThreshold:
            return VStack(alignment: .leading, spacing: 8) {
                Text("Default: 20% increase").bold()
                Text(
                    "Maximum allowed positive percent change in glucose level to permit SMBs. If the difference in glucose is greater than this, Trio will disable SMBs."
                )
                Text("Note: This setting has a hard-coded cap of 40%")
            }
        case .highTempTargetRaisesSensitivity:
            return VStack(alignment: .leading, spacing: 8) {
                Text("Default: OFF").bold()
                Text(
                    "When this feature is enabled, manually setting a temporary target above \(units == .mgdL ? "100" : 100.formattedAsMmolL) \(units.rawValue) will decrease the Autosens Ratio used for ISF and basal adjustments, resulting in less insulin delivered overall. This scales with the temporary target set; the higher the temp target, the lower the Autosens Ratio used."
                )
                Text(
                    "If Half Basal Exercise Target is set to \(units == .mgdL ? "160" : 160.formattedAsMmolL) \(units.rawValue), a temp target of \(units == .mgdL ? "120" : 120.formattedAsMmolL) \(units.rawValue) uses an Autosens Ratio of 0.75. A temp target of \(units == .mgdL ? "140" : 140.formattedAsMmolL) \(units.rawValue) uses an Autosens Ratio of 0.6."
                )
                Text("Note: The effect of this can be adjusted with the Half Basal Exercise Target")
            }
        case .lowTempTargetLowersSensitivity:
            return VStack(alignment: .leading, spacing: 8) {
                Text("Default: OFF").bold()
                Text(
                    "When this feature is enabled, setting a temporary target below \(units == .mgdL ? "100" : 100.formattedAsMmolL) \(units.rawValue) will increase the Autosens Ratio used for ISF and basal adjustments, resulting in more insulin delivered overall. This scales with the temporary target set; the lower the Temp Target, the higher the Autosens Ratio used. It requires Algorithm Settings > Autosens > Autosens Max to be set to > 100% to work."
                )
                Text(
                    "If Half Basal Exercise Target is \(units == .mgdL ? "160" : 160.formattedAsMmolL) \(units.rawValue), a Temp Target of \(units == .mgdL ? "95" : 95.formattedAsMmolL) \(units.rawValue) uses an Autosens Ratio of 1.09. A Temp Target of \(units == .mgdL ? "85" : 85.formattedAsMmolL) \(units.rawValue) uses an Autosens Ratio of 1.33."
                )
                Text("Note: The effect of this can be adjusted with the Half Basal Exercise Target")
            }
        case .sensitivityRaisesTarget:
            return VStack(alignment: .leading, spacing: 8) {
                Text("Default: OFF").bold()
                Text(
                    "Enabling this feature causes Trio to automatically raise the targeted glucose if it detects an increase in insulin sensitivity from your baseline."
                )
            }
        case .resistanceLowersTarget:
            return VStack(alignment: .leading, spacing: 8) {
                Text("Default: OFF").bold()
                Text(
                    "Enabling this feature causes Trio to automatically reduce the targeted glucose if it detects a decrease in sensitivity (resistance) from your baseline."
                )
            }
        case .halfBasalTarget:
            return VStack(alignment: .leading, spacing: 8) {
                Text(
                    "Default: \(units == .mgdL ? "160" : 160.formattedAsMmolL) \(units.rawValue)"
                )
                .bold()
                Text(
                    "The Half Basal Exercise Target allows you to scale down your basal insulin during exercise or scale up your basal insulin when eating soon when a temporary glucose target is set."
                )
                Text(
                    "For example, at a temp target of \(units == .mgdL ? "160" : 160.formattedAsMmolL) \(units.rawValue), your basal is reduced to 50%, but this scales depending on the target (e.g., 75% at \(units == .mgdL ? "120" : 120.formattedAsMmolL) \(units.rawValue), 60% at \(units == .mgdL ? "140" : 140.formattedAsMmolL) \(units.rawValue))."
                )
                Text(
                    "Note: This setting is only utilized if the settings \"Low Temp Target Lowers Sensitivity\" OR \"High Temp Target Raises Sensitivity\" are enabled."
                )
            }
        }
    }
}

enum DiagnosticsSharingOption: String, Equatable, CaseIterable, Identifiable {
    case enabled
    case disabled

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .enabled:
            return "Enable Sharing"
        case .disabled:
            return "Disable Sharing"
        }
    }
}

enum PumpOptionForOnboardingUnits: String, Equatable, CaseIterable, Identifiable {
    case minimed
    case omnipodEros
    case omnipodDash
    case dana

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .minimed:
            return "Medtronic"
        case .omnipodEros:
            return "Omnipod Eros"
        case .omnipodDash:
            return "Omnipod Dash"
        case .dana:
            return "Dana (RS/-i)"
        }
    }
}

enum NightscoutSetupOption: String, Equatable, CaseIterable, Identifiable {
    case setupNightscout
    case skipNightscoutSetup
    case noSelection

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .setupNightscout:
            return String(localized: "Setup Nightscout for Trio")
        case .skipNightscoutSetup:
            return String(localized: "Skip Nightscout Setup")
        case .noSelection:
            return ""
        }
    }
}

enum NightscoutImportOption: String, Equatable, CaseIterable, Identifiable {
    case useImport
    case skipImport
    case noSelection

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .useImport:
            return String(localized: "Import Settings")
        case .skipImport:
            return String(localized: "Configure Yourself")
        case .noSelection:
            return ""
        }
    }
}

enum NightscoutSubstep: Int, CaseIterable, Identifiable {
    case setupSelection
    case connectToNightscout
    case importFromNightscout

    var id: Int { rawValue }
}

struct BulletPoint: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        HStack(alignment: .top) {
            Text("•")
            Text(text)
        }
    }
}

enum OnboardingSettingItemType: Equatable, CaseIterable, Identifiable {
    case overview
    case complete

    var id: UUID {
        UUID()
    }
}

enum OnboardingInputSectionType: Equatable {
    case decimal
    case boolean

    static func == (lhs: OnboardingInputSectionType, rhs: OnboardingInputSectionType) -> Bool {
        switch (lhs, rhs) {
        case (.boolean, .boolean):
            return true
        case (.decimal, .decimal):
            return true
        default:
            return false
        }
    }
}

/// A reusable view for displaying setting items in the completed step.
struct SettingItemView: View {
    let step: OnboardingStep
    let icon: String
    let title: String
    let type: OnboardingSettingItemType

    private var accentColor: Color {
        switch type {
        case .overview:
            Color.blue
        case .complete:
            Color.green
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            if step == .nightscout {
                Image(icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 40, height: 24)
                    .colorMultiply(accentColor)
            } else {
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundStyle(accentColor)
                    .frame(width: 40)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
            }

            Spacer()

            switch type {
            case .overview:
                let index = nonInfoOnboardingSteps.firstIndex(of: step) ?? 0
                let stepNumber = index + 1
                Text(stepNumber.description)
                    .bold()
                    .frame(width: 32, height: 32, alignment: .center)
                    .background(accentColor)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            case .complete:
                Image(systemName: "checkmark")
                    .foregroundStyle(accentColor)
            }
        }
        .padding(.vertical, 8)
    }
}
