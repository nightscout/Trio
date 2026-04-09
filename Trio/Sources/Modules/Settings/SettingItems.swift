import Foundation
import LoopKitUI
import SwiftUI

struct SettingItem: Identifiable {
    let id = UUID()
    let title: String
    let view: Screen
    let searchContents: [String]?
    let path: [String]?
    /// Maps a `searchContents` string to the exact label used in `SettingInputSection`
    /// when the two differ (e.g. `"Max IOB"` → `"Maximum Insulin on Board (IOB)"`).
    /// Entries whose searchContents string already matches the label don't need an entry here.
    let scrollTargetLabels: [String: String]?

    init(
        title: String,
        view: Screen,
        searchContents: [String]? = nil,
        scrollTargetLabels: [String: String]? = nil,
        path: [String]? = nil
    ) {
        self.title = title
        self.view = view
        self.searchContents = searchContents
        self.scrollTargetLabels = scrollTargetLabels
        self.path = path
    }
}

struct FilteredSettingItem: Identifiable {
    let id = UUID()
    let settingItem: SettingItem
    let matchedContent: String
    /// The label string used as the scroll/highlight target in the destination view.
    /// Falls back to `matchedContent` when no explicit mapping exists.
    var scrollLabel: String {
        settingItem.scrollTargetLabels?[matchedContent] ?? matchedContent
    }
}

enum SettingItems {
    static let trioConfig = [
        SettingItem(title: String(localized: "Devices", comment: "Devices menu item in the Settings main view."), view: .devices),
        SettingItem(
            title: String(localized: "Therapy", comment: "Therapy menu item in the Settings main view."),
            view: .therapySettings
        ),
        SettingItem(
            title: String(localized: "Algorithm", comment: "Algorithm menu item in the Settings main view."),
            view: .algorithmSettings
        ),
        SettingItem(
            title: String(localized: "Features", comment: "Features menu item in the Settings main view."),
            view: .featureSettings
        ),
        SettingItem(
            title: String(localized: "Notifications", comment: "Notifications menu item in the Settings main view."),
            view: .notificationSettings
        ),
        SettingItem(
            title: String(localized: "Services", comment: "Services menu item in the Settings main view."),
            view: .serviceSettings
        )
    ]

    static let devicesItems = [
        SettingItem(title: "Insulin Pump", view: .pumpConfig, path: ["Devices"]),
        SettingItem(
            title: "CGM",
            view: .cgm,
            searchContents: ["Smooth Glucose Value"],
            path: ["Devices", "Continuous Glucose Monitor"]
        ),
        SettingItem(title: "Smart Watch", view: .watch, path: ["Devices"]),
        SettingItem(
            title: "Apple Watch",
            view: .watch,
            searchContents: ["Display on Watch", "Show Protein and Fat", "Confirm Bolus Faster"],
            path: ["Devices", "Smart Watch", "Apple Watch"]
        ),
        SettingItem(
            title: "Contact Image",
            view: .watch,
            searchContents: ["Display on Watch", "Watch Complication"],
            path: ["Devices", "Smart Watch", "Apple Watch", "Contact Image"]
        )
    ]

    static let therapyItems = [
        SettingItem(
            title: "Units and Limits",
            view: .unitsAndLimits,
            searchContents: [
                "Glucose Units",
                "Max Basal",
                "Max Bolus",
                "Max IOB",
                "Max COB",
                "Minimum Safety Threshold",
                "Delivery Limits"
            ],
            scrollTargetLabels: [
                "Max IOB": "Maximum Insulin on Board (IOB)",
                "Max Bolus": "Maximum Bolus",
                "Max Basal": "Maximum Basal Rate",
                "Max COB": "Maximum Carbs on Board (COB)"
            ],
            path: ["Therapy Settings", "Units and Limits"]
        ),
        SettingItem(title: "Basal Rates", view: .basalProfileEditor, path: ["Therapy Settings"]),
        SettingItem(title: "Insulin Sensitivities", view: .isfEditor, path: ["Therapy Settings"]),
        SettingItem(title: "ISF", view: .isfEditor, path: ["Therapy Settings"]),
        SettingItem(title: "Carb Ratios", view: .crEditor, path: ["Therapy Settings"]),
        SettingItem(title: "CR", view: .crEditor, path: ["Therapy Settings"]),
        SettingItem(title: "Glucose Targets", view: .targetsEditor, path: ["Therapy Settings"])
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
                "Enable SMB With COB",
                "Enable SMB With Temporary Target",
                "Enable SMB After Carbs",
                "Enable SMB With High Glucose",
                "High Glucose Target",
                "Allow SMB With High Temporary Target",
                "Enable UAM",
                "Max SMB Basal Minutes",
                "Max UAM SMB Basal Minutes",
                "Max Allowed Glucose Rise for SMB"
            ],
            scrollTargetLabels: [
                "Enable SMB With Temporary Target": "Enable SMB With Temptarget",
                "Allow SMB With High Temporary Target": "Allow SMB With High Temptarget",
                "Max UAM SMB Basal Minutes": "Max UAM Basal Minutes",
                "High Glucose Target": "Enable SMB With High Glucose"
            ],
            path: ["Algorithm", "Super Micro Bolus (SMB)"]
        ),
        SettingItem(
            title: "Dynamic Settings",
            view: .dynamicISF,
            searchContents: [
                "Dynamic ISF",
                "Sigmoid",
                "Logarithmic",
                "Adjustment Factor (AF)",
                "Sigmoid Adjustment Factor",
                "Weighted Average of TDD",
                "Adjust Basal"
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
            scrollTargetLabels: [
                "High Temptarget Raises Sensitivity": "High Temp Target Raises Sensitivity",
                "Low Temptarget Lowers Sensitivity": "Low Temp Target Lowers Sensitivity"
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
                "Duration of Insulin Action", "DIA",
                "Insulin Peak Time",
                "Skip Neutral Temps",
                "Unsuspend If No Temp",
                "SMB Delivery Ratio",
                "SMB Interval",
                "Min 5m Carbimpact",
                "Remaining Carbs Fraction",
                "Remaining Carbs Cap",
                "Noisy CGM Target Multiplier"
            ],
            scrollTargetLabels: [
                "Min 5m Carbimpact": "Min 5m Carb Impact",
                "Remaining Carbs Fraction": "Remaining Carbs Percentage",
                "Noisy CGM Target Multiplier": "Noisy CGM Target Increase"
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
                "Enable Reduced Bolus Option",
                "Reduced Bolus Percentage",
                "Enable Reduced Bolus Factor",
                "Reduced Bolus Factor",
                "Enable Super Bolus Option",
                "Super Bolus Percentage",
                "Enable Super Bolus",
                "Super Bolus Factor",
                "Very Low Glucose Warning"
            ],
            scrollTargetLabels: [
                "Reduced Bolus Percentage": "Enable Reduced Bolus Option",
                "Enable Reduced Bolus Factor": "Enable Reduced Bolus Option",
                "Reduced Bolus Factor": "Enable Reduced Bolus Option",
                "Super Bolus Percentage": "Enable Super Bolus Option",
                "Enable Super Bolus": "Enable Super Bolus Option",
                "Super Bolus Factor": "Enable Super Bolus Option"
            ],
            path: ["Features", "Bolus Calculator"]
        ),
        SettingItem(
            title: "Meal Settings",
            view: .mealSettings,
            searchContents: [
                "Max Carbs",
                "Max Meal Absorption Time",
                "Max Fat",
                "Max Protein",
                "Enable Fat and Protein Entries",
                "Fat and Protein Delay",
                "Spread Interval",
                "Fat and Protein Percentage",
                "FPU"
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
            title: "Remote Control",
            view: .remoteControlConfig,
            searchContents: ["Remote Control"],
            path: ["Features", "Remote Control"]
        ),
        SettingItem(
            title: "User Interface",
            view: .userInterfaceSettings,
            searchContents: [
                "Show X-Axis Grid Lines",
                "Show Y-Axis Grid Lines",
                "Show Low and High Thresholds",
                "Low Threshold",
                "High Threshold",
                "eA1c/GMI Display Unit",
                "Show Carbs Required Badge",
                "Carbs Required Threshold",
                "Forecast Display Type",
                "Bolus Display Threshold",
                "Cone",
                "Lines",
                "Appearance",
                "Dark Mode",
                "Light Mode",
                "Dark Scheme",
                "Light Scheme",
                "Glucose Color Scheme",
                "Time in Range Type",
                "Time in Tight Range (TITR)",
                "Time in Normoglycemia (TING)",
                "X-Axis Interval Step"
            ],
            scrollTargetLabels: [
                "Show Y-Axis Grid Lines": "Show X-Axis Grid Lines",
                "High Threshold": "Low Threshold",
                "Cone": "Forecast Display Type",
                "Lines": "Forecast Display Type",
                "Dark Mode": "Appearance",
                "Light Mode": "Appearance",
                "Time in Tight Range (TITR)": "Time in Range Type",
                "Time in Normoglycemia (TING)": "Time in Range Type",
                "Dark Scheme": "Appearance",
                "Light Scheme": "Appearance",
                "X-Axis Interval Step": "Show X-Axis Grid Lines",
                "Carbs Required Threshold": "Show Carbs Required Badge"
            ],
            path: ["Features", "User Interface"]
        ),
        SettingItem(
            title: "App Icons",
            view: .iconConfig,
            searchContents: ["Trio Icon"],
            path: ["Features", "App Icons"]
        ),
        SettingItem(
            title: "App Diagnostics",
            view: .appDiagnostics,
            searchContents: ["Anonymized Data Sharing"],
            path: ["Features", "App Diagnostics"]
        )
    ]

    static let notificationItems = [
        SettingItem(title: "Manage iOS Preferences", view: .notificationSettings),
        SettingItem(
            title: "Trio Notifications",
            view: .glucoseNotificationSettings,
            searchContents: [
                "Always Notify Pump",
                "Always Notify CGM",
                "Always Notify Carb",
                "Always Notify Algorithm",
                "Show Glucose App Badge",
                "Glucose Notifications",
                "Add Glucose Source to Alarm",
                "Low Glucose Alarm Limit",
                "High Glucose Alarm Limit"
            ],
            path: ["Notifications", "Trio Notifications"] // Glucose
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
        SettingItem(title: "Tidepool", view: .serviceSettings, path: ["Services"]),
        SettingItem(title: "Apple Health", view: .healthkit, path: ["Services"])
    ]

    static var allItems: [SettingItem] {
        trioConfig + devicesItems + therapyItems + algorithmItems + trioFeaturesItems + notificationItems + serviceItems
    }

    static func filteredItems(searchText: String) -> [FilteredSettingItem] {
        allItems.flatMap { item in
            var results = [FilteredSettingItem]()
            let searchLower = searchText.lowercased()

            let titleLocalized = item.title.localized
            let titleEnglish = item.title.englishLocalized

            if titleLocalized.localizedCaseInsensitiveContains(searchLower) ||
                titleEnglish.localizedCaseInsensitiveContains(searchLower)
            {
                results.append(FilteredSettingItem(settingItem: item, matchedContent: item.title))
            }

            if let contents = item.searchContents {
                let matched = contents.filter {
                    $0.localized.localizedCaseInsensitiveContains(searchLower) ||
                        $0.englishLocalized.localizedCaseInsensitiveContains(searchLower)
                }
                results.append(contentsOf: matched.map { FilteredSettingItem(settingItem: item, matchedContent: $0) })
            }

            return results
        }
    }
}

extension String {
    func localizedString(locale: Locale = .current) -> String {
        if locale.identifier == "en",
           let path = Bundle.main.path(forResource: "en", ofType: "lproj"),
           let bundle = Bundle(path: path)
        {
            return NSLocalizedString(self, bundle: bundle, comment: "")
        }
        return NSLocalizedString(self, comment: "")
    }

    var localized: String { localizedString() }
    var englishLocalized: String { localizedString(locale: Locale(identifier: "en")) }
}
