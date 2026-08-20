import Combine
import Foundation

enum OpenSourceClinicConfigModule {
    enum Config {
        static let urlKey = OpenSourceClinicConfig.Keys.url
        static let tokenKey = OpenSourceClinicConfig.Keys.token
        static let isEnabledKey = OpenSourceClinicConfig.Keys.isEnabled
        static let syncIntervalKey = OpenSourceClinicConfig.Keys.syncInterval
    }
}

protocol OpenSourceClinicConfigProvider: Provider {
    func testConnection(url: String, token: String) async throws
}
