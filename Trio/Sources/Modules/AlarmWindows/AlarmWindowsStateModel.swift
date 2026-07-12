import Combine
import SwiftUI

extension AlarmWindows {
    final class StateModel: BaseStateModel<Provider> {
        @Published var units: GlucoseUnits = .mgdL

        override func subscribe() {
            units = settingsManager.settings.units
        }
    }
}

extension AlarmWindows.StateModel: SettingsObserver {
    func settingsDidChange(_: TrioSettings) {
        units = settingsManager.settings.units
    }
}
