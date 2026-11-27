import CryptoKit
import Foundation
import Testing

@testable import Trio

@Suite("Secure Messenger Tests") struct SecureMessengerTests {
    private let secret = "s3cret"
    private let bolusJSON = #"{"user":"caregiver","command_type":"bolus","timestamp":1700000000,"bolus_amount":1.5}"#

    /// Encrypts the way LoopFollow does: AES-GCM keyed by SHA-256 of the secret, nonce + ciphertext + tag, base64.
    private func encrypt(_ json: String, secret: String) throws -> String {
        let key = SymmetricKey(data: SHA256.hash(data: Data(secret.utf8)))
        return try #require(AES.GCM.seal(Data(json.utf8), using: key).combined).base64EncodedString()
    }

    private func decrypt(_ encrypted: String, secret: String) throws -> CommandPayload {
        try SecureMessenger(sharedSecret: secret).decrypt(base64EncodedString: encrypted)
    }

    @Test("Decrypts a command sealed with the same secret") func decryptsCommand() throws {
        #expect(try decrypt(encrypt(bolusJSON, secret: secret), secret: secret).commandType == .bolus)
    }

    @Test("A different secret fails authentication") func differentSecret() throws {
        let encrypted = try encrypt(bolusJSON, secret: secret)
        #expect(throws: SecureMessengerError.authenticationFailed) { try decrypt(encrypted, secret: "other") }
    }

    @Test("Text that is not base64 is an invalid message") func invalidBase64() {
        #expect(throws: SecureMessengerError.invalidMessage) { try decrypt("not base64!", secret: secret) }
    }

    @Test("Data too short for a nonce and tag is an invalid message") func tooShort() {
        #expect(throws: SecureMessengerError.invalidMessage) {
            try decrypt(Data(count: 10).base64EncodedString(), secret: secret)
        }
    }

    @Test("A command Trio cannot decode is undecodable, not an authentication failure") func undecodableCommand() throws {
        let encrypted = try encrypt(#"{"user":"caregiver"}"#, secret: secret)
        let error = #expect(throws: SecureMessengerError.self) { try decrypt(encrypted, secret: secret) }
        guard case .undecodableCommand? = error else {
            Issue.record("Expected undecodableCommand, got \(String(describing: error))")
            return
        }
    }
}
