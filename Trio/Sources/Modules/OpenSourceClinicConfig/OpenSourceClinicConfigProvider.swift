import Foundation

extension OpenSourceClinicConfigModule {
    final class Provider: BaseProvider, OpenSourceClinicConfigProvider {
        @Injected() var openSourceClinicManager: OpenSourceClinicManager!
        @Injected() var keychain: Keychain!

        func testConnection(url: String, token: String) async throws {
            UserDefaults.standard.set(url, forKey: OpenSourceClinicConfig.Keys.url)
            UserDefaults.standard.set(token, forKey: OpenSourceClinicConfig.Keys.token)
            try await openSourceClinicManager.testConnection()
        }
    }
}
