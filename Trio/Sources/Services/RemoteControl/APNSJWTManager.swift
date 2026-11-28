import CryptoKit
import Foundation
import os

final class APNSJWTManager: Sendable {
    static let shared = APNSJWTManager()

    private init() {}

    private struct CacheKey: Hashable {
        let keyId: String
        let teamId: String
        let apnsKey: String
    }

    private struct CachedToken {
        let token: String
        let expiresAt: Date
    }

    private struct Claims: Encodable {
        let iss: String
        let iat: Int
    }

    private let cache = OSAllocatedUnfairLock(initialState: [CacheKey: CachedToken]())

    func getOrGenerateJWT(keyId: String, teamId: String, apnsKey: String) -> String? {
        let key = CacheKey(keyId: keyId, teamId: teamId, apnsKey: apnsKey)

        // Held while signing, so confirmations sent at the same moment share one token.
        return cache.withLock { cache in
            if let cached = cache[key], Date() < cached.expiresAt {
                return cached.token
            }
            do {
                let token = try Self.signedToken(keyId: keyId, teamId: teamId, apnsKey: apnsKey)

                // APNs rejects tokens older than an hour, so refresh five minutes early.
                cache[key] = CachedToken(token: token, expiresAt: Date().addingTimeInterval(55 * 60))
                return token
            } catch {
                warning(.remote, "Failed to sign push response token", error: error)
                return nil
            }
        }
    }

    private static func signedToken(keyId: String, teamId: String, apnsKey: String) throws -> String {
        let header = try JSONEncoder().encode(["alg": "ES256", "kid": keyId])
        let claims = try JSONEncoder().encode(Claims(iss: teamId, iat: Int(Date().timeIntervalSince1970)))
        let signingInput = "\(header.base64URL).\(claims.base64URL)"
        let signature = try signingKey(from: apnsKey).signature(for: Data(signingInput.utf8))

        return "\(signingInput).\(signature.rawRepresentation.base64URL)"
    }

    private static func signingKey(from apnsKey: String) throws -> P256.Signing.PrivateKey {
        let base64 = apnsKey.replacingOccurrences(of: "-----[^-]+-----", with: "", options: .regularExpression)
        guard let der = Data(base64Encoded: base64, options: .ignoreUnknownCharacters) else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "The APNs key is not valid base64."))
        }
        return try P256.Signing.PrivateKey(derRepresentation: der)
    }
}

private extension Data {
    // Foundation's .base64URLAlphabet and .omitPaddingCharacter need iOS 26.4; switch once the deployment target allows.
    var base64URL: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
