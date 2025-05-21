import Foundation

extension WatchConfig {
    final class Provider: BaseProvider, WatchConfigProvider {
        @Injected() private var settingsManager: SettingsManager!
        private let processQueue = DispatchQueue(label: "WatchDeviceProvider.processQueue")

        var preferences: Preferences {
            settingsManager.preferences
        }

        func savePreferences(_ preferences: Preferences) {
            processQueue.async {
                var prefs = preferences
                prefs.timestamp = Date()
                self.storage.save(prefs, as: OpenAPS.Settings.preferences)
            }
        }
    }
}
