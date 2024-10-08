import Combine
import SwiftUI

extension LiveActivitySettings {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() var storage: FileStorage!

        @Published var units: GlucoseUnits = .mgdL
        @Published var useLiveActivity = false
        @Published var lockScreenView: LockScreenView = .simple
        @Published var showChart: Bool = true
        @Published var showCurrentGlucose: Bool = true
        @Published var showChangeLabel: Bool = true
        @Published var showIOB: Bool = true
        @Published var showCOB: Bool = true
        @Published var showUpdatedLabel: Bool = true

        override func subscribe() {
            units = settingsManager.settings.units

            subscribeSetting(\.useLiveActivity, on: $useLiveActivity) { useLiveActivity = $0 }
            subscribeSetting(\.lockScreenView, on: $lockScreenView) { lockScreenView = $0 }

            subscribeSetting(\.showChart, on: $showChart) { showChart = $0 }
            subscribeSetting(\.showCurrentGlucose, on: $showCurrentGlucose) { showCurrentGlucose = $0 }
            subscribeSetting(\.showChangeLabel, on: $showChangeLabel) { showChangeLabel = $0 }
            subscribeSetting(\.showIOB, on: $showIOB) { showIOB = $0 }
            subscribeSetting(\.showCOB, on: $showCOB) { showCOB = $0 }
            subscribeSetting(\.showUpdatedLabel, on: $showUpdatedLabel) { showUpdatedLabel = $0 }
        }
    }
}

extension LiveActivitySettings.StateModel: SettingsObserver {
    func settingsDidChange(_: FreeAPSSettings) {
        units = settingsManager.settings.units
        showChart = settingsManager.settings.showChart
        showCurrentGlucose = settingsManager.settings.showCurrentGlucose
        showChangeLabel = settingsManager.settings.showChangeLabel
        showIOB = settingsManager.settings.showIOB
        showCOB = settingsManager.settings.showCOB
        showUpdatedLabel = settingsManager.settings.showUpdatedLabel
    }
}
