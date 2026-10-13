import Foundation

#if canImport(AlarmKit)
    import AlarmKit
    import SwiftUI

    @available(iOS 26.0, *) struct MealTimeReminderMetadata: AlarmMetadata {
        let carbs: Double

        let bolusAmount: Double

        let bolusDate: Date
    }

    @available(iOS 26.0, *) enum MealTimeReminderStyle {
        // Matches carbs are orange convention
        static let tint = Color.orange
    }
#endif
