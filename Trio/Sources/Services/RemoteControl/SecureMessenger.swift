import CryptoSwift
import Foundation
import Security

struct SecureMessenger {
    private let sharedKey: [UInt8]

    init?(sharedSecret: String) {
        guard let secretData = sharedSecret.data(using: .utf8) else {
            return nil
        }
        sharedKey = Array(secretData.sha256())
    }

    func decrypt(base64EncodedString: String) throws -> CommandPayload {
        guard let combinedData = Data(base64Encoded: base64EncodedString) else {
            throw NSError(domain: "SecureMessenger", code: 100, userInfo: [NSLocalizedDescriptionKey: "Invalid Base64 string"])
        }

        let nonceSize = 12
        guard combinedData.count > nonceSize else {
            throw NSError(
                domain: "SecureMessenger",
                code: 101,
                userInfo: [NSLocalizedDescriptionKey: "Encrypted data is too short to contain a nonce"]
            )
        }
        let nonce = Array(combinedData.prefix(nonceSize))
        let ciphertextAndTag = Array(combinedData.suffix(from: nonceSize))
        let gcm = GCM(iv: nonce, mode: .combined)
        let aes = try AES(key: sharedKey, blockMode: gcm, padding: .noPadding)
        let decryptedBytes = try aes.decrypt(ciphertextAndTag)
        let decryptedData = Data(decryptedBytes)
        let commandPayload = try JSONDecoder().decode(CommandPayload.self, from: decryptedData)

        return commandPayload
    }
}
