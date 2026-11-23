import CryptoKit
import Foundation
import os
import Testing

@testable import Trio

@Suite("APNs JWT Manager Tests") struct APNSJWTManagerTests {
    @Test("Signs an ES256 token with the APNs key, however it was pasted") func signsPastedKeys() throws {
        let key = P256.Signing.PrivateKey()
        let pem = key.pemRepresentation
        let lines = pem.split(separator: "\n").map(String.init)
        let pasted = [
            "as is": pem,
            "CRLF": lines.joined(separator: "\r\n"),
            "blank lines around": "  \n\(pem)\n\n  ",
            "indented": lines.map { "    \($0)" }.joined(separator: "\n"),
            "one line with spaces": lines.joined(separator: " "),
            "one line": lines.joined(),
            "quoted": "\"\(pem)\"",
            "line-end spaces": lines.map { "\($0) " }.joined(separator: "\n")
        ]
        for (format, apnsKey) in pasted {
            // A fresh key id each time, because tokens are cached per key.
            let token = try #require(
                APNSJWTManager.shared.getOrGenerateJWT(keyId: UUID().uuidString, teamId: "TEAM123456", apnsKey: apnsKey),
                "\(format)"
            )
            let parts = token.split(separator: ".")
            try #require(parts.count == 3, "\(format)")
            #expect(isSigned(token, by: key), "\(format)")
            let claims = try JSONSerialization.jsonObject(with: try #require(Data(base64URL: parts[1]))) as? [String: Any]
            #expect(claims?["iss"] as? String == "TEAM123456")
            #expect(claims?["iat"] is Int)
        }
    }

    @Test("A corrected key gets a new token") func correctedKey() throws {
        let keyId = UUID().uuidString
        let wrongKey = P256.Signing.PrivateKey(), rightKey = P256.Signing.PrivateKey()
        _ = APNSJWTManager.shared.getOrGenerateJWT(keyId: keyId, teamId: "TEAM123456", apnsKey: wrongKey.pemRepresentation)
        let token = try #require(
            APNSJWTManager.shared
                .getOrGenerateJWT(keyId: keyId, teamId: "TEAM123456", apnsKey: rightKey.pemRepresentation)
        )
        #expect(isSigned(token, by: rightKey))
    }

    @Test("Confirmations sent at the same moment share one token") func oneTokenAtATime() {
        let keyId = UUID().uuidString, apnsKey = P256.Signing.PrivateKey().pemRepresentation
        let tokens = OSAllocatedUnfairLock(initialState: Set<String?>())
        DispatchQueue.concurrentPerform(iterations: 16) { _ in
            let token = APNSJWTManager.shared.getOrGenerateJWT(keyId: keyId, teamId: "TEAM123456", apnsKey: apnsKey)
            tokens.withLock { _ = $0.insert(token) }
        }
        #expect(tokens.withLock { $0.count } == 1)
    }

    private func isSigned(_ token: String, by key: P256.Signing.PrivateKey) -> Bool {
        let parts = token.split(separator: ".").map(String.init)
        guard parts.count == 3, let raw = Data(base64URL: parts[2]),
              let signature = try? P256.Signing.ECDSASignature(rawRepresentation: raw) else { return false }
        return key.publicKey.isValidSignature(signature, for: Data("\(parts[0]).\(parts[1])".utf8))
    }
}

private extension Data {
    init?(base64URL: some StringProtocol) {
        let base64 = base64URL.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        self.init(base64Encoded: base64 + String(repeating: "=", count: (4 - base64.count % 4) % 4))
    }
}
