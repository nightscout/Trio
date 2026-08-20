import Combine
import Foundation

extension OpenSourceClinicConfigModule {
    final class StateModel: BaseStateModel<OpenSourceClinicConfigModule.Provider> {
        @Published var url: String = ""
        @Published var token: String = ""
        @Published var isEnabled: Bool = false
        @Published var syncInterval: TimeInterval = 300
        @Published var isTesting: Bool = false
        @Published var testResult: String?
        @Published var lastSyncDate: Date?

        override func subscribe() {
            url = UserDefaults.standard.string(forKey: OpenSourceClinicConfig.Keys.url)
                ?? OpenSourceClinicConfig.Defaults.url
            token = provider.keychain.getValue(String.self, forKey: OpenSourceClinicConfig.Keys.token).value ?? ""
            isEnabled = UserDefaults.standard.bool(forKey: OpenSourceClinicConfig.Keys.isEnabled)
            syncInterval = UserDefaults.standard.double(forKey: OpenSourceClinicConfig.Keys.syncInterval)
            if syncInterval == 0 { syncInterval = OpenSourceClinicConfig.Defaults.syncInterval }
            lastSyncDate = provider.openSourceClinicManager.lastSyncDate
        }

        func save() {
            UserDefaults.standard.set(url, forKey: OpenSourceClinicConfig.Keys.url)
            UserDefaults.standard.set(isEnabled, forKey: OpenSourceClinicConfig.Keys.isEnabled)
            UserDefaults.standard.set(syncInterval, forKey: OpenSourceClinicConfig.Keys.syncInterval)
            provider.keychain.setValue(token, forKey: OpenSourceClinicConfig.Keys.token)
        }

        func testConnection() async {
            isTesting = true
            testResult = nil
            do {
                try await provider.testConnection(url: url, token: token)
                testResult = "Connection successful"
            } catch {
                testResult = "Failed: \(error.localizedDescription)"
            }
            isTesting = false
        }

        func syncNow() async {
            save()
            await provider.openSourceClinicManager.syncAll()
            lastSyncDate = provider.openSourceClinicManager.lastSyncDate
        }
    }
}
