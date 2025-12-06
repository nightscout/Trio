import Foundation
import SwiftJWT

struct APNSJWTClaims: Claims {
    let iss: String
    let iat: Date
}

class APNSJWTManager {
    static let shared = APNSJWTManager()

    private init() {}

    private struct JWTCacheKey: Hashable {
        let keyId: String
        let teamId: String
    }

    private struct CachedJWT {
        let token: String
        let expirationDate: Date
    }

    // Cache multiple JWTs for different LoopFollow instances
    private var jwtCache: [JWTCacheKey: CachedJWT] = [:]
    private let cacheQueue = DispatchQueue(label: "com.trio.apnsjwtmanager.cache", attributes: .concurrent)

    func getOrGenerateJWT(keyId: String, teamId: String, apnsKey: String) -> String? {
        let cacheKey = JWTCacheKey(keyId: keyId, teamId: teamId)

        // Check cache first
        if let cachedJWT = getCachedJWT(for: cacheKey) {
            return cachedJWT
        }

        // Generate new JWT
        let header = Header(kid: keyId)
        let claims = APNSJWTClaims(iss: teamId, iat: Date())
        var jwt = JWT(header: header, claims: claims)

        do {
            let privateKey = Data(apnsKey.utf8)
            let jwtSigner = JWTSigner.es256(privateKey: privateKey)
            let signedJWT = try jwt.sign(using: jwtSigner)

            // Cache the JWT with 55 minute expiration (5 minute buffer before 1 hour)
            let expirationDate = Date().addingTimeInterval(3300)
            cacheJWT(signedJWT, for: cacheKey, expirationDate: expirationDate)

            return signedJWT
        } catch {
            debug(.remoteControl, "Failed to sign JWT: \(error.localizedDescription)")
            return nil
        }
    }

    private func getCachedJWT(for key: JWTCacheKey) -> String? {
        cacheQueue.sync {
            guard let cached = jwtCache[key],
                  Date() < cached.expirationDate
            else {
                return nil
            }
            return cached.token
        }
    }

    private func cacheJWT(_ token: String, for key: JWTCacheKey, expirationDate: Date) {
        cacheQueue.async(flags: .barrier) {
            self.jwtCache[key] = CachedJWT(token: token, expirationDate: expirationDate)
        }
    }

    func invalidateCache() {
        cacheQueue.async(flags: .barrier) {
            self.jwtCache.removeAll()
        }
    }
}
