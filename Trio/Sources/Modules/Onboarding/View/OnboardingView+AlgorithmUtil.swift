//
//  OnboardingView+AlgorithmUtil.swift
//  Trio
//
//  Created by Cengiz Deniz on 15.04.25.
//
import SwiftUI

protocol AlgorithmSubstepProtocol: Identifiable, RawRepresentable {
    var title: String { get }
    func hint(units: GlucoseUnits) -> String
    func description(units: GlucoseUnits) -> any View
}

extension AlgorithmSubstepProtocol {
    var title: String {
        AlgorithmSettingMeta(rawValue: String(describing: self))?.title ?? ""
    }

    func hint(units: GlucoseUnits) -> String {
        AlgorithmSettingMeta(rawValue: String(describing: self))?.hint(units: units) ?? ""
    }

    func description(units: GlucoseUnits) -> any View {
        AlgorithmSettingMeta(rawValue: String(describing: self))?.description(units: units) ?? AnyView(EmptyView())
    }
}

extension AlgorithmSubstepProtocol where Self: RawRepresentable, Self.RawValue == Int {
    func toAlgorithmSubstep() -> AlgorithmSettingsSubstep? {
        switch self {
        case let step as AutosensSettingsSubstep:
            return [
                .autosensMin,
                .autosensMax,
                .rewindResetsAutosens
            ][step.rawValue]
        case let step as SMBSettingsSubstep:
            return [
                .enableSMBAlways,
                .enableSMBWithCOB,
                .enableSMBWithTempTarget,
                .enableSMBAfterCarbs,
                .enableSMBWithHighGlucoseTarget,
                .allowSMBWithHighTempTarget,
                .enableUAM,
                .maxSMBMinutes,
                .maxUAMMinutes,
                .maxDeltaGlucoseThreshold
            ][step.rawValue]
        case let step as TargetBehaviorSubstep:
            return [
                .highTempTargetRaisesSensitivity,
                .lowTempTargetLowersSensitivity,
                .sensitivityRaisesTarget,
                .resistanceLowersTarget,
                .halfBasalTarget
            ][step.rawValue]
        default:
            return nil
        }
    }
}

extension View {
    func eraseToAnyView() -> AnyView {
        AnyView(self)
    }
}

enum AlgorithmSettingsOverviewSubstep: Int, CaseIterable, Identifiable {
    case contents
    case importantNotes

    var id: Int { rawValue }
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
        case .autosensMin: return String(localized: "Autosens Minimum", comment: "Autosens Min")
        case .autosensMax: return String(localized: "Autosens Maximum", comment: "Autosens Max")
        case .rewindResetsAutosens: return String(localized: "Rewind Resets Autosens", comment: "Rewind Resets Autosens")
        case .enableSMBAlways: return String(localized: "Enable SMB Always", comment: "Enable SMB Always")
        case .enableSMBWithCOB: return String(localized: "Enable SMB With COB", comment: "Enable SMB With COB")
        case .enableSMBWithTempTarget: return String(
                localized: "Enable SMB With Temptarget",
                comment: "Enable SMB With Temptarget"
            )
        case .enableSMBAfterCarbs: return String(localized: "Enable SMB After Carbs", comment: "Enable SMB After Carbs")
        case .enableSMBWithHighGlucoseTarget: return String(
                localized: "Enable SMB With High Glucose",
                comment: "Enable SMB With High Glucose"
            )
        case .allowSMBWithHighTempTarget: return String(
                localized: "Allow SMB With High Temptarget",
                comment: "Allow SMB With High Temptarget"
            )
        case .enableUAM: return String(localized: "Enable UAM (Unannounced Meals)", comment: "Enable UAM")
        case .maxSMBMinutes: return String(localized: "Max SMB Basal Minutes", comment: "Max SMB Basal Minutes")
        case .maxUAMMinutes: return String(localized: "Max UAM Basal Minutes", comment: "Max UAM Basal Minutes")
        case .maxDeltaGlucoseThreshold: return String(
                localized: "Max. Allowed Glucose Rise for SMB",
                comment: "Max. Allowed Glucose Rise for SMB, formerly Max Delta-BG Threshold"
            )
        case .highTempTargetRaisesSensitivity: return String(
                localized: "High Temp Target Raises Sensitivity",
                comment: "High Temp Target Raises Sensitivity"
            )
        case .lowTempTargetLowersSensitivity: return String(
                localized:
                "Low Temp Target Lowers Sensitivity",
                comment: "Low Temp Target Lowers Sensitivity"
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
        case .enableSMBWithHighGlucoseTarget: return String(localized: "Allow SMB when glucose is above the High Glucose Target value.")
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
        case .sensitivityRaisesTarget: return String(localized: "Raise target glucose when Autosens Ratio is less than 1.")
        case .resistanceLowersTarget: return String(localized: "Lower target glucose when Autosens Ratio is greater than 1.")
        case .halfBasalTarget: return String(localized: "Scales down your basal rate to 50% at this value.")
        }
    }

    func description(units: GlucoseUnits) -> any View {
        switch self {
        case .autosensMin:
            return VStack(alignment: .leading, spacing: 8) {
                Text("Default: 70%").bold().foregroundStyle(Color.primary)
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
                Text("Default: 120%").bold().foregroundStyle(Color.primary)
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
            return VStack(alignment: .leading, spacing: 5) {
                Text("Default: ON").bold().foregroundStyle(Color.primary)
                Text("Medtronic and Dana Users Only").bold()
                VStack(alignment: .leading, spacing: 8) {
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
            }
        case .enableSMBAlways:
            return VStack(alignment: .leading, spacing: 8) {
                Text(
                    "Enabling SMB Always will disable some of the subsequent \"Enable SMB\" options during Onboarding. These redundant options will be skipped."
                )
                .padding(.bottom)
                .foregroundStyle(Color.orange)

                Text("Default: OFF").bold().foregroundStyle(Color.primary)
                Text(
                    "When enabled, Super Micro Boluses (SMBs) will always be allowed if dosing calculations determine insulin is needed via the SMB delivery method, except when a high Temp Target is set."
                )
                Text(
                    "Note: If you would like to allow SMBs when a high Temp Target is set, enable the \"Allow SMBs with High Temptarget\" setting."
                )
            }
        case .enableSMBWithCOB:
            return VStack(alignment: .leading, spacing: 8) {
                Text("Default: OFF").bold().foregroundStyle(Color.primary)
                Text(
                    "When the carb on board (COB) forecast line is active, enabling this feature allows Trio to use Super Micro Boluses (SMB) to deliver the insulin required."
                )
                Text(
                    "Note: If this is enabled and the criteria are met, SMBs could be utilized regardless of other SMB settings being enabled or not."
                )
            }
        case .enableSMBWithTempTarget:
            return VStack(alignment: .leading, spacing: 8) {
                Text("Default: OFF").bold().foregroundStyle(Color.primary)
                Text(
                    "Enabling this feature allows Trio to deliver insulin required using Super Micro Boluses (SMB) at times when a manual Temporary Target under \(units == .mgdL ? "100" : 100.formattedAsMmolL) \(units.rawValue) is set."
                )
                Text(
                    "Note: If this is enabled and the criteria are met, SMBs could be utilized regardless of other SMB settings being enabled or not."
                )
            }
        case .enableSMBAfterCarbs:
            return VStack(alignment: .leading, spacing: 8) {
                Text("Default: OFF").bold().foregroundStyle(Color.primary)
                Text(
                    "Enabling this feature allows Trio to deliver insulin required using Super Micro Boluses (SMB) for 6 hours after a carb entry, regardless of whether there are active carbs on board (COB)."
                )
                Text(
                    "Note: If this is enabled and the criteria are met, SMBs could be utilized regardless of other SMB settings being enabled or not."
                )
            }
        case .enableSMBWithHighGlucoseTarget:
            return VStack(alignment: .leading, spacing: 8) {
                Text("Default: OFF").bold().foregroundStyle(Color.primary)
                Text(
                    "Enabling this feature allows Trio to deliver insulin required using Super Micro Boluses (SMB) when glucose reading is above the value set as High Glucose Target."
                )
                Text(
                    "Note: If this is enabled and the criteria are met, SMBs could be utilized regardless of other SMB settings being enabled or not."
                )
            }
        case .allowSMBWithHighTempTarget:
            return VStack(alignment: .leading, spacing: 8) {
                Text("Default: OFF").bold().foregroundStyle(Color.primary)
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
                Text("Default: OFF").bold().foregroundStyle(Color.primary)
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
                    Text("Default: 30 minutes").bold().foregroundStyle(Color.primary)
                    Text("(50% current basal rate)")
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
                    Text("Default: 30 minutes").bold().foregroundStyle(Color.primary)
                    Text("(50% current basal rate)")

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
                Text("Default: 20% increase").bold().foregroundStyle(Color.primary)
                Text(
                    "Maximum allowed positive percent change in glucose level to permit SMBs. If the difference in glucose is greater than this, Trio will disable SMBs."
                )
                Text(
                    "This is a safety limitation to avoid high SMB doses when glucose is rising abnormally fast, such as after a meal or with a very jumpy CGM sensor."
                )
                Text("Note: This setting has a hard-coded cap of 40%")
            }
        case .highTempTargetRaisesSensitivity:
            return VStack(alignment: .leading, spacing: 8) {
                Text("Default: OFF").bold().foregroundStyle(Color.primary)
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
                Text("Default: OFF").bold().foregroundStyle(Color.primary)
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
                Text("Default: OFF").bold().foregroundStyle(Color.primary)
                Text(
                    "Enabling this feature causes Trio to automatically raise the targeted glucose if it detects an increase in insulin sensitivity from your baseline."
                )
            }
        case .resistanceLowersTarget:
            return VStack(alignment: .leading, spacing: 8) {
                Text("Default: OFF").bold().foregroundStyle(Color.primary)
                Text(
                    "Enabling this feature causes Trio to automatically reduce the targeted glucose if it detects a decrease in sensitivity (resistance) from your baseline."
                )
            }
        case .halfBasalTarget:
            return VStack(alignment: .leading, spacing: 8) {
                Text(
                    "Default: \(units == .mgdL ? "160" : 160.formattedAsMmolL) \(units.rawValue)"
                )
                .bold().foregroundStyle(Color.primary)
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

    init?(rawValue: String) {
        self.init(rawValue: AlgorithmSettingsSubstep.allCases.first { rawValue == "\($0)" }?.rawValue ?? -1)
    }
}

// MARK: - Algorithm Settings Substep Groups

enum AutosensSettingsSubstep: Int, CaseIterable, Identifiable {
    case autosensMin
    case autosensMax
    case rewindResetsAutosens

    var id: Int { rawValue }
}

enum SMBSettingsSubstep: Int, CaseIterable, Identifiable {
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

    var id: Int { rawValue }
}

enum TargetBehaviorSubstep: Int, CaseIterable, Identifiable {
    case highTempTargetRaisesSensitivity
    case lowTempTargetLowersSensitivity
    case sensitivityRaisesTarget
    case resistanceLowersTarget
    case halfBasalTarget

    var id: Int { rawValue }
}

extension AutosensSettingsSubstep: AlgorithmSubstepProtocol {}
extension SMBSettingsSubstep: AlgorithmSubstepProtocol {}
extension TargetBehaviorSubstep: AlgorithmSubstepProtocol {}

// MARK: - Shared Metadata Helper

enum AlgorithmSettingMeta: String {
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

    var title: String {
        AlgorithmSettingsSubstep(rawValue: rawValue)?.title ?? ""
    }

    func hint(units: GlucoseUnits) -> String {
        AlgorithmSettingsSubstep(rawValue: rawValue)?.hint(units: units) ?? ""
    }

    func description(units: GlucoseUnits) -> any View {
        AlgorithmSettingsSubstep(rawValue: rawValue)?.description(units: units) ?? AnyView(EmptyView())
    }
}
