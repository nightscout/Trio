import Combine
import SwiftUI

extension LiveActivitySettings {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() var storage: FileStorage!

        @Published var units: GlucoseUnits = .mgdL
        @Published var useLiveActivity = false
        @Published var lockScreenView: LockScreenView = .simple
        override func subscribe() {
            units = settingsManager.settings.units
            subscribeSetting(\.useLiveActivity, on: $useLiveActivity) { useLiveActivity = $0 }
            subscribeSetting(\.lockScreenView, on: $lockScreenView) { lockScreenView = $0 }
        }
    }
}

extension LiveActivitySettings.StateModel: SettingsObserver {
    func settingsDidChange(_: TrioSettings) {
        units = settingsManager.settings.units
    }
}
