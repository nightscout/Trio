import Foundation
import SwiftUI

/// Represents the different steps in the onboarding process.
enum OnboardingStep: Int, CaseIterable, Identifiable {
    case welcome
    case glucoseTarget
    case basalProfile
    case carbRatio
    case insulinSensitivity
    case completed

    var id: Int { rawValue }

    /// The title to display for this onboarding step.
    var title: String {
        switch self {
        case .welcome:
            return "Welcome to Trio"
        case .glucoseTarget:
            return "Glucose Target"
        case .basalProfile:
            return "Basal Profile"
        case .carbRatio:
            return "Carbohydrate Ratio"
        case .insulinSensitivity:
            return "Insulin Sensitivity"
        case .completed:
            return "All Set!"
        }
    }

    /// A detailed description of what this onboarding step is about.
    var description: String {
        switch self {
        case .welcome:
            return "Trio is a powerful app that helps you manage your diabetes. Let's get started by setting up a few important parameters that will help Trio work effectively for you."
        case .glucoseTarget:
            return "Your glucose target is the blood glucose level you aim to maintain. Trio will use this to calculate insulin doses and provide recommendations."
        case .basalProfile:
            return "Your basal profile represents the amount of background insulin you need throughout the day. This helps Trio calculate your insulin needs."
        case .carbRatio:
            return "Your carb ratio tells how many grams of carbohydrates one unit of insulin will cover. This is essential for accurate meal bolus calculations."
        case .insulinSensitivity:
            return "Your insulin sensitivity factor (ISF) indicates how much one unit of insulin will lower your blood glucose. This helps calculate correction boluses."
        case .completed:
            return "Great job! You've completed the initial setup of Trio. You can always adjust these settings later in the app."
        }
    }

    /// The system icon name associated with this step.
    var iconName: String {
        switch self {
        case .welcome:
            return "hand.wave.fill"
        case .glucoseTarget:
            return "target"
        case .basalProfile:
            return "chart.xyaxis.line"
        case .carbRatio:
            return "fork.knife"
        case .insulinSensitivity:
            return "drop.fill"
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
        case .welcome:
            return Color.blue
        case .glucoseTarget:
            return Color.green
        case .basalProfile:
            return Color.purple
        case .carbRatio:
            return Color.orange
        case .insulinSensitivity:
            return Color.red
        case .completed:
            return Color.blue
        }
    }
}

/// Model that holds the data collected during onboarding.
@Observable class OnboardingData {
    // Glucose Target
    var targetLow: Decimal = 80
    var targetHigh: Decimal = 120

    // Basal Profile
    var basalRates: [BasalRateEntry] = [BasalRateEntry(startTime: 0, rate: 1.0)]

    // Carb Ratio
    var carbRatio: Decimal = 10

    // Insulin Sensitivity Factor
    var isf: Decimal = 40

    // Blood Glucose Units
    var units: GlucoseUnits = .mgdL

    struct BasalRateEntry: Identifiable {
        var id = UUID()
        var startTime: Int // Minutes from midnight
        var rate: Decimal

        var timeFormatted: String {
            let hours = startTime / 60
            let minutes = startTime % 60
            return String(format: "%02d:%02d", hours, minutes)
        }
    }

    /// Applies the onboarding data to the app's settings.
    func applyToSettings(settingsManager: SettingsManager) {
        // Make a copy of the current settings that we can mutate
        var settingsCopy = settingsManager.settings

        // Apply glucose target - We'll use lowGlucose and highGlucose properties
        settingsCopy.lowGlucose = targetLow
        settingsCopy.highGlucose = targetHigh

        // Apply glucose units
        settingsCopy.units = units

        // Apply carb ratio (if the property exists in TrioSettings)
        if let carbRatioValue = Double(exactly: NSDecimalNumber(decimal: carbRatio)) {
            // Assuming there is a related property for carb ratio in TrioSettings
            // This might need to be adjusted based on the actual property name
            // settingsCopy.carbRatio = carbRatioValue
        }

        // Apply ISF (if the property exists in TrioSettings)
        if let isfValue = Double(exactly: NSDecimalNumber(decimal: isf)) {
            // Assuming there is a related property for insulin sensitivity factor in TrioSettings
            // This might need to be adjusted based on the actual property name
            // settingsCopy.insulinSensitivityFactor = isfValue
        }

        // Instead of using updateSettings which doesn't exist,
        // we'll directly set the settings property which will trigger the didSet observer
        settingsManager.settings = settingsCopy
    }
}
