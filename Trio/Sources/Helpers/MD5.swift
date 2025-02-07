import CryptoKit
import Foundation

extension Data {
    var md5String: String {
        let digest = Insecure.MD5.hash(data: self)
        return digest.map {
            String(format: "%02hhx", $0)
        }.joined()
    }
}

extension String {
    var md5String: String {
        (data(using: .utf8) ?? Data()).md5String
    }
}
