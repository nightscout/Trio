import CryptoKit
import Foundation

struct SecureMessenger {
    private let key: SymmetricKey

    init(sharedSecret: String) {
        key = SymmetricKey(data: SHA256.hash(data: Data(sharedSecret.utf8)))
    }

    func decrypt(base64EncodedString: String) throws -> CommandPayload {
        guard let combined = Data(base64Encoded: base64EncodedString) else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Invalid Base64 string"))
        }
        let box = try AES.GCM.SealedBox(combined: combined)
        return try JSONDecoder().decode(CommandPayload.self, from: AES.GCM.open(box, using: key))
    }
}
