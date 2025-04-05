import SwiftUI

/// Represents the different steps in the onboarding process.
enum OnboardingStep: Int, CaseIterable, Identifiable, Equatable {
    case welcome
    case diagnostics
    case nightscout
    case unitSelection
    case glucoseTarget
    case basalProfile
    case carbRatio
    case insulinSensitivity
    case deliveryLimits
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
        case .diagnostics:
            return String(localized: "Diagnostics")
        case .nightscout:
            return String(localized: "Nightscout")
        case .unitSelection:
            return String(localized: "Units & Pump")
        case .glucoseTarget:
            return String(localized: "Glucose Target")
        case .basalProfile:
            return String(localized: "Basal Profile")
        case .carbRatio:
            return String(localized: "Carbohydrate Ratio")
        case .insulinSensitivity:
            return String(localized: "Insulin Sensitivity")
        case .deliveryLimits:
            return String(localized: "Delivery Limits")
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
        case .basalProfile:
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
                localized: "Trio offers various delivery limits which represent the maximum amount of insulin it can deliver at a time. This helps ensure safe and effective experience."
            )
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
        case .diagnostics:
            return "waveform.badge.magnifyingglass"
        case .nightscout:
            return "owl"
        case .unitSelection:
            return "numbers.rectangle"
        case .glucoseTarget:
            return "target"
        case .basalProfile:
            return "chart.xyaxis.line"
        case .carbRatio:
            return "fork.knife"
        case .insulinSensitivity:
            return "drop.fill"
        case .deliveryLimits:
            return "slider.horizontal.3"
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
        case .completed,
             .deliveryLimits,
             .diagnostics,
             .nightscout,
             .unitSelection,
             .welcome:
            return Color.blue
        case .glucoseTarget:
            return Color.green
        case .basalProfile:
            return Color.purple
        case .carbRatio:
            return Color.orange
        case .insulinSensitivity:
            return Color.red
        }
    }
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
        case .maxBasal: return String(localized: "Max Basal")
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

enum DiagnostisSharingOption: String, Equatable, CaseIterable, Identifiable {
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

enum PumpOptionsForOnboardingUnits: String, Equatable, CaseIterable, Identifiable {
    case minimed
    case omnipodEros
    case omnipodDash
    case dana

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .minimed:
            return "Medtronic 5xx / 7xx"
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
