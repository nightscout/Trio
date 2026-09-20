import Combine
import SwiftUI

extension LiveActivitySettings {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() var storage: FileStorage!

        @Published var units: GlucoseUnits = .mgdL
        @Published var useLiveActivity = false
        @Published var lockScreenView: LockScreenView = .simple
        @Published var smartStackView: LockScreenView = .simple
        @Published var displayGlucoseForecasts = false
        @Published var simpleFontFace: LiveActivityFontFace = .default
        @Published var simpleFontSize: LiveActivityFontSize = .large
        @Published var simpleUseGlucoseColor = false

        /// Glucose color scheme the app applies everywhere, used to preview the Simple widget's reading color.
        var glucoseColorScheme: GlucoseColorScheme { settingsManager.settings.glucoseColorScheme }
        /// User-set high glucose threshold, used to preview the Simple widget's reading color.
        var highGlucose: Decimal { settingsManager.settings.high }
        /// User-set low glucose threshold, used to preview the Simple widget's reading color.
        var lowGlucose: Decimal { settingsManager.settings.low }

        override func subscribe() {
            units = settingsManager.settings.units
            subscribeSetting(\.useLiveActivity, on: $useLiveActivity) { useLiveActivity = $0 }
            subscribeSetting(\.lockScreenView, on: $lockScreenView) { lockScreenView = $0 }
            subscribeSetting(\.smartStackView, on: $smartStackView) { smartStackView = $0 }
            subscribeSetting(\.displayGlucoseForecasts, on: $displayGlucoseForecasts) { displayGlucoseForecasts = $0 }
            subscribeSetting(\.liveActivitySimpleFontFace, on: $simpleFontFace) { simpleFontFace = $0 }
            subscribeSetting(\.liveActivitySimpleFontSize, on: $simpleFontSize) { simpleFontSize = $0 }
            subscribeSetting(\.liveActivitySimpleUseGlucoseColor, on: $simpleUseGlucoseColor) { simpleUseGlucoseColor = $0 }
        }
    }
}

extension LiveActivitySettings.StateModel: SettingsObserver {
    func settingsDidChange(_: TrioSettings) {
        units = settingsManager.settings.units
    }
}
