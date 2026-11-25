import CryptoKit
import Foundation

enum SecureMessengerError: Error, Equatable {
    /// Not base64, or too short to hold a nonce and tag.
    case invalidMessage
    /// The AES-GCM tag did not verify: the message was sealed with a different key.
    case authenticationFailed
    /// Decrypted, but not a command this version can decode. Carries the decoding error for the log.
    case undecodableCommand(String)
}

struct SecureMessenger {
    private let key: SymmetricKey

    init(sharedSecret: String) {
        key = SymmetricKey(data: SHA256.hash(data: Data(sharedSecret.utf8)))
    }

    func decrypt(base64EncodedString: String) throws (SecureMessengerError) -> CommandPayload {
        guard let combined = Data(base64Encoded: base64EncodedString),
              let box = try? AES.GCM.SealedBox(combined: combined)
        else { throw .invalidMessage }

        guard let json = try? AES.GCM.open(box, using: key) else { throw .authenticationFailed }

        do {
            return try JSONDecoder().decode(CommandPayload.self, from: json)
        } catch {
            throw .undecodableCommand(String(describing: error))
        }
    }
}
