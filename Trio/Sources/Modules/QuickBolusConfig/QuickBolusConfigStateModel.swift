import SwiftUI

extension QuickBolusConfig {
    final class StateModel: BaseStateModel<Provider> {
        @Published var enableQuickBolus: Bool = false

        override func subscribe() {
            subscribeSetting(\.enableQuickBolus, on: $enableQuickBolus) { enableQuickBolus = $0 }
        }
    }
}

extension QuickBolusConfig.StateModel: SettingsObserver {
    func settingsDidChange(_: TrioSettings) {}
}
