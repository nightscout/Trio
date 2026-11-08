import Foundation

/// Shared by the home-screen countdown banner and the Live Activity widget so the two surfaces
/// can't drift out of sync.
enum MealTimeReminderSummary {
    /// "45 g · 2.4 U", omitting either half when it is zero.
    static func compact(carbs: Double, bolusAmount: Double) -> String {
        var parts: [String] = []
        if carbs > 0 {
            parts.append(String(
                localized: "\(Int(carbs.rounded())) g",
                comment: "Carb amount in grams in the meal-time reminder summary"
            ))
        }
        if bolusAmount > 0 {
            parts.append(String(
                localized: "\(bolusAmount, specifier: "%.2f") U",
                comment: "Insulin amount in units in the meal-time reminder summary"
            ))
        }
        return parts.joined(separator: " · ")
    }
}

#if canImport(AlarmKit)
    import AlarmKit
    import SwiftUI

    @available(iOS 26.0, *) struct MealTimeReminderMetadata: AlarmMetadata {
        let carbs: Double

        let bolusAmount: Double
    }

    @available(iOS 26.0, *) enum MealTimeReminderStyle {
        // Matches carbs are orange convention
        static let tint = Color.orange
    }
#endif
