import Foundation

#if canImport(AlarmKit)
    import AlarmKit
    import SwiftUI

    @available(iOS 26.0, *) struct PreBolusAlarmMetadata: AlarmMetadata {
        let carbs: Double

        let bolusAmount: Double

        let bolusDate: Date
    }

    @available(iOS 26.0, *) enum PreBolusAlarmStyle {
        // Matches carbs are orange convention
        static let tint = Color.orange
    }
#endif
