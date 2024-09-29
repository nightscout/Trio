import SwiftUI

extension RemoteControlConfig {
    final class StateModel: BaseStateModel<Provider> {
        @Published var units: GlucoseUnits = .mgdL
        @Published var isTRCEnabled: Bool = false
        @Published var sharedSecret: String = ""

        override func subscribe() {
            units = settingsManager.settings.units
            isTRCEnabled = UserDefaults.standard.bool(forKey: "TRCenabled")
            sharedSecret = UserDefaults.standard.string(forKey: "TRCsharedSecret") ?? generateInitialSharedSecret()

            $isTRCEnabled
                .receive(on: DispatchQueue.main)
                .sink { value in
                    UserDefaults.standard.set(value, forKey: "TRCenabled")
                }
                .store(in: &lifetime)

            $sharedSecret
                .receive(on: DispatchQueue.main)
                .sink { value in
                    UserDefaults.standard.set(value, forKey: "TRCsharedSecret")
                }
                .store(in: &lifetime)
        }

        func generateNewSharedSecret() {
            let newSecret = UUID().uuidString.replacingOccurrences(of: "-", with: "")
            sharedSecret = newSecret
            UserDefaults.standard.set(newSecret, forKey: "TRCsharedSecret")
        }

        private func generateInitialSharedSecret() -> String {
            let secret = UUID().uuidString.replacingOccurrences(of: "-", with: "")
            UserDefaults.standard.set(secret, forKey: "TRCsharedSecret")
            return secret
        }
    }
}

extension RemoteControlConfig.StateModel: SettingsObserver {
    func settingsDidChange(_: FreeAPSSettings) {
        units = settingsManager.settings.units
    }
}
