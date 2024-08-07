import Foundation
import LoopKitUI
import SwiftUI

struct SettingItem: Identifiable {
    let id = UUID()
    let title: LocalizedStringKey
    let view: Screen
    let searchContents: [LocalizedStringKey]?
    let path: [LocalizedStringKey]?

    init(
        title: LocalizedStringKey,
        view: Screen,
        searchContents: [LocalizedStringKey]? = nil,
        path: [LocalizedStringKey]? = nil
    ) {
        self.title = title
        self.view = view
        self.searchContents = searchContents
        self.path = path
    }
}

struct FilteredSettingItem: Identifiable {
    let id = UUID()
    let settingItem: SettingItem
    let matchedContent: LocalizedStringKey
}

// TODO: fill this shit here with content...

enum SettingItems {
    static let trioConfig = [
        SettingItem(title: "Devices", view: .devices),
        SettingItem(title: "Therapy", view: .therapySettings),
        SettingItem(title: "Algorithm", view: .algorithmSettings),
        SettingItem(title: "Features", view: .featureSettings),
        SettingItem(title: "Notifications", view: .notificationSettings),
        SettingItem(title: "Services", view: .serviceSettings)
    ]

    static let devicesItems = [
        SettingItem(title: "Insulin Pump", view: .pumpConfig),
        SettingItem(
            title: "Delivery Limits & DIA",
            view: .cgm,
            searchContents: ["Max Basal", "Max Bolus", "Duration of Insulin Action", "DIA"],
            path: ["Devices", "Insulin Pump", "Delivery Limits & DIA"]
        ),
        SettingItem(
            title: "CGM",
            view: .cgm,
            searchContents: ["Smooth Glucose Value"],
            path: ["Devices", "Continuous Glucose Monitor"]
        ),
        SettingItem(title: "Smart Watch", view: .watch),
        SettingItem(
            title: "Apple Watch",
            view: .watch,
            searchContents: ["Display on Watch", "Show Protein and Fat", "Confirm Bolus Faster"],
            path: ["Devices", "Smart Watch", "Apple Watch"]
        )
    ]

    static let therapyItems = [
        SettingItem(
            title: "Units and Limits",
            view: .unitsAndLimits,
            searchContents: ["Glucose Units", "Max IOB", "Max COB"],
            path: ["Therapy Settings", "Units and Limits"]
        ),
        SettingItem(title: "Basal Rates", view: .basalProfileEditor),
        SettingItem(title: "Insulin Sensitivities", view: .isfEditor),
        SettingItem(title: "ISF", view: .isfEditor),
        SettingItem(title: "Carb Ratios", view: .crEditor),
        SettingItem(title: "CR", view: .crEditor),
        SettingItem(title: "Target Glucose", view: .targetsEditor)
    ]

    static let algorithmItems = [
        SettingItem(
            title: "Autosens",
            view: .autosensSettings,
            searchContents: ["Autosens Max", "Autosens Min", "Rewind Resets Autosens"],
            path: ["Algorithm", "Autosens"]
        ),
        SettingItem(
            title: "Super Micro Bolus (SMB)",
            view: .smbSettings,
            searchContents: [
                "Enable SMB Always",
                "Max SMB Basal Minutes",
                "Max UAM SMB Basal Minutes",
                "Max Delta-BG Threshold SMB",
                "SMB Delivery Ratio",
                "SMB Interval"
            ],
            path: ["Algorithm", "Super Micro Bolus (SMB)"]
        ),
        SettingItem(
            title: "Dynamic Sensitivity",
            view: .dynamicISF,
            searchContents: [
                "Activate Dynamic Sensitivity (ISF)",
                "Activate Dynamic Carb Ratio (CR)",
                "Use Sigmoid Formula",
                "Adjustment Factor",
                "Sigmoid Adjustment Factor",
                "Weighted Average of TDD",
                "Adjust Basal",
                "Threshold Setting"
            ],
            path: ["Algorithm", "Dynamic Sensitivity"]
        ),
        SettingItem(
            title: "Target Behavior",
            view: .targetBehavior,
            searchContents: [
                "High Temptarget Raises Sensitivity",
                "Low Temptarget Lowers Sensitivity",
                "Sensitivity Raises Target",
                "Resistance Lowers Target",
                "Half Basal Exercise Target"
            ],
            path: ["Algorithm", "Target Behavior"]
        ),
        SettingItem(
            title: "Additionals",
            view: .algorithmAdvancedSettings,
            searchContents: [
                "Max Daily Safety Multiplier",
                "Current Basal Safety Multiplier",
                "Use Custom Peak Time",
                "Insulin Peak Time",
                "Skip Neutral Temps",
                "Unsuspend If No Temp",
                "Suspend Zeros IOB",
                "Min 5m Carbimpact",
                "Autotune ISF Adjustment Fractio",
                "Remaining Carbs Fraction",
                "Remaining Carbs Cap",
                "Noisy CGM Target Multiplier"
            ],
            path: ["Algorithm", "Additionals"]
        )
    ]

    static let trioFeaturesItems = [
        SettingItem(
            title: "Bolus Calculator",
            view: .bolusCalculatorConfig,
            searchContents: [
                "Display Meal Presets",
                "Recommended Bolus Percentage",
                "Enable Fatty Meal Factor",
                "Fatty Meal Factor",
                "Enable Super Bolus",
                "Super Bolus Factor"
            ],
            path: ["Features", "Bolus Calculator"]
        ),
        SettingItem(
            title: "Meal Settings",
            view: .mealSettings,
            searchContents: [
                "Max Carbs",
                "Max Fat",
                "Max Protein",
                "Display and Allow Fat and Protein Entries",
                "Fat and Protein Delay",
                "Maximum Duration (hours)",
                "Spread Interval (minutes)",
                "Fat and Protein Factor"
            ],
            path: ["Features", "Meal Settings"]
        ),
        SettingItem(
            title: "Shortcuts",
            view: .shortcutsConfig,
            searchContents: ["Allow Bolusing with Shortcuts"],
            path: ["Features", "Shortcuts"]
        ),
        SettingItem(
            title: "User Interface",
            view: .userInterfaceSettings,
            searchContents: [
                "Show X-Axis Grid Lines",
                "Show Y-Axis Grid Line",
                "Show Low and High Thresholds",
                "Low Threshold",
                "High Threshold",
                "X-Axis Interval Step",
                "Total Insulin Display Type",
                "Total Daily Dose",
                "Total Insulin in Scope",
                "Override HbA1c Unit",
                "Standing / Laying TIR Chart",
                "Show Carbs Required Badge",
                "Carbs Required Threshold"
            ],
            path: ["Features", "User Interface"]
        ),
        SettingItem(title: "App Icons", view: .iconConfig),
        SettingItem(title: "Autotune", view: .autotuneConfig)
    ]

    static let notificationItems = [
        SettingItem(
            title: "Glucose Notifications",
            view: .glucoseNotificationSettings,
            searchContents: [
                "Show Glucose App Badge",
                "Always Notify Glucose",
                "Play Alarm Sound",
                "Add Glucose Source to Alarm",
                "Low Glucose Alarm Limit",
                "High Glucose Alarm Limit"
            ],
            path: ["Notifications", "Glucose Notifications"]
        ),
        SettingItem(
            title: "Live Activity",
            view: .liveActivitySettings,
            searchContents: [
                "Enable Live Activity",
                "Lock Screen Widget Style"
            ],
            path: ["Notifications", "Live Activity"]
        ),
        SettingItem(
            title: "Calendar Events",
            view: .calendarEventSettings,
            searchContents: [
                "Create Calendar Events",
                "Choose Calendar",
                "Display Emojis as Labels",
                "Display IOB and COB"
            ],
            path: ["Notifications", "Calendar Events"]
        )
    ]

    static let serviceItems = [
        SettingItem(
            title: "Nightscout",
            view: .nighscoutConfig,
            searchContents: [
                "Import Settings",
                "Backfill Glucose"
            ],
            path: ["Services", "Nightscout"]
        ),
        SettingItem(
            title: "Nightscout Upload",
            view: .nighscoutConfig,
            searchContents: [
                "Allow Uploading to Nightscout",
                "Upload Glucose"
            ],
            path: ["Services", "Nightscout", "Upload"]
        ),
        SettingItem(
            title: "Nightscout Fetch & Remote Control",
            view: .nighscoutConfig,
            searchContents: [
                "Allow Fetching From Nightscout"
            ],
            path: ["Services", "Nightscout", "Fetch and Remote Control"]
        ),
        SettingItem(title: "Tidepool", view: .serviceSettings),
        SettingItem(title: "Apple Health", view: .healthkit)
    ]

    static var allItems: [SettingItem] {
        trioConfig + devicesItems + therapyItems + algorithmItems + trioFeaturesItems + notificationItems + serviceItems
    }

    static func filteredItems(searchText: String) -> [FilteredSettingItem] {
        allItems.compactMap { item in
            if item.title.stringValue.localizedCaseInsensitiveContains(searchText) {
                return FilteredSettingItem(settingItem: item, matchedContent: item.title)
            }
            if let matchedContent = item.searchContents?
                .first(where: { $0.stringValue.localizedCaseInsensitiveContains(searchText) })
            {
                return FilteredSettingItem(settingItem: item, matchedContent: matchedContent)
            }
            return nil
        }
    }
}

extension LocalizedStringKey {
    var stringValue: String {
        let mirror = Mirror(reflecting: self)
        let children = mirror.children
        if let label = children.first(where: { $0.label == "key" })?.value as? String {
            return NSLocalizedString(label, comment: "")
        } else {
            return ""
        }
    }
}
