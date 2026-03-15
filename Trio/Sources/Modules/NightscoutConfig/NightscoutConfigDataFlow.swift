import Combine
import Foundation

enum NightscoutConfig {
    enum Config {
        static let urlKey = "NightscoutConfig.url"
        static let secretKey = "NightscoutConfig.secret"
    }
}

protocol NightscoutConfigProvider: Provider {
    func checkConnection(url: URL, secret: String?) -> AnyPublisher<Void, Error>
}
