import Foundation

enum OpenSourceClinicConfig {
    enum Keys {
        static let url = "OpenSourceClinic.url"
        static let token = "OpenSourceClinic.token"
        static let isEnabled = "OpenSourceClinic.isEnabled"
        static let syncInterval = "OpenSourceClinic.syncInterval"
    }

    enum Defaults {
        static let url = "https://api.opensource.clinic"
        static let syncInterval: TimeInterval = 300 // 5 min
    }
}
