import CryptoKit
import DeviceCheck
import Foundation
import Swinject

struct TelemetryRequestContext {
    let reason: String
    let lastFailureReason: String?
    let trioVersion: String
    let installID: String

    func applyHeaders(to request: inout URLRequest) {
        request.setValue(trioVersion, forHTTPHeaderField: "X-Trio-Version")
        request.setValue(installID, forHTTPHeaderField: "X-Trio-InstallId")
    }
}

// MARK: - TelemetryAttestor

/// Apple App Attest wrapper for the telemetry uploader. Owns:
///   - the per-install App Attest key (generated once, persisted in Keychain)
///   - the "this install has been registered with the server" flag (Keychain)
///   - challenge fetch + assertion generation per send cycle
///
/// Designed to fail soft: if the device doesn't support App Attest
/// (simulators, older iOS, etc.), `isSupported` is false and the caller
/// should silently skip the send. Server-side rejections (403 from the
/// register endpoint) are sticky — recorded in PropertyPersistentFlags so
/// subsequent cycles don't retry indefinitely.
///
/// Wire protocol matches `nightscout/trio-telemetry`:
///   1. POST /api/auth/ios/challenge       → { "challenge": "<base64url>" }
///   2. POST /api/attest/register          (once per install)
///   3. /checkin                           (per ping, headers below)
final class TelemetryAttestor: Injectable {
    static let shared = TelemetryAttestor()

    @Injected() private var keychain: Keychain!

    private let service = DCAppAttestService.shared
    private let lock = NSRecursiveLock()
    private var didInjectServices = false

    private static let keyIDStorageKey = "TelemetryAttest.keyID"
    private static let registeredStorageKey = "TelemetryAttest.registered"

    private init() {}

    private func injectIfNeeded() {
        lock.lock()
        defer { lock.unlock() }
        guard !didInjectServices else { return }
        injectServices(TrioApp.resolver)
        didInjectServices = true
    }

    /// True when the running device supports App Attest. Returns false on the
    /// simulator and on devices that lack a Secure Enclave.
    var isSupported: Bool {
        service.isSupported
    }

    /// True once a 403 from `/api/attest/register` has flagged this install
    /// as permanently rejected — typically a misconfigured `app_id`. Callers
    /// should stop attempting to send.
    var isForbidden: Bool {
        PropertyPersistentFlags.shared.telemetryAttestForbidden == true
    }

    // MARK: - Registration

    /// Idempotent: returns immediately if already registered. Otherwise
    /// performs `generateKey` → fetch challenge → `attestKey`, resolves the
    /// app ID, then POSTs the registration.
    /// Throws on transport / server errors; sets the sticky "forbidden" flag
    /// on a 403 so future cycles short-circuit.
    func registerIfNeeded(baseURL: URL, context: TelemetryRequestContext) async throws {
        injectIfNeeded()

        guard isSupported else { throw AttestError.unsupportedDevice }
        guard !isForbidden else { throw AttestError.forbidden }

        if (keychain.getValue(Bool.self, forKey: Self.registeredStorageKey) ?? false) == true {
            return
        }

        // generateKey() returns a base64url-encoded key identifier (Apple's docs).
        // We persist it as-is for use in the assertion path below.
        let keyID = try await currentOrCreateKeyID()
        let challenge = try await fetchChallenge(
            baseURL: baseURL,
            context: context
        )

        // App Attest expects a SHA-256 of the "client data" — for the
        // attestation step, that's the challenge bytes alone.
        let challengeBytes = Data(challenge.utf8)
        let clientDataHash = Data(SHA256.hash(data: challengeBytes))

        // Diagnostics for `attestKey` failures. We log shape, not values:
        // keyID prefix only (the keyID is per-install and shouldn't end up in
        // shareable logs in full). If any of these look off, the failure is
        // ours; if they look right and Apple still rejects, the failure is
        // server-side at Apple.
        let keyIDPrefix = String(keyID.prefix(8))
        debug(
            .telemetry,
            "attestKey input: isSupported=\(service.isSupported) keyID.count=\(keyID.count) keyID.prefix=\(keyIDPrefix) hash.count=\(clientDataHash.count) challenge.count=\(challenge.count) bundle=\(Bundle.main.bundleIdentifier ?? "nil")"
        )

        let attestationCBOR: Data
        do {
            attestationCBOR = try await service.attestKey(keyID, clientDataHash: clientDataHash)
        } catch {
            // `attestKey` is one-shot per key per device, but only on success.
            // Branch on the DCError code so logs distinguish the recoverable
            // cases from real failures:
            //   .invalidKey         — keyID is permanently burnt; drop it.
            //   .invalidInput       — Apple rejected an argument as malformed.
            //                         In practice we see this when the keyID
            //                         is stale (e.g. survived an uninstall via
            //                         Keychain) and no longer matches Apple's
            //                         expected identity for this install. Drop
            //                         the keyID — same recovery as invalidKey.
            //   .serverUnavailable  — Apple's App Attest backend is down or
            //                         throttling. Key is still valid; the
            //                         next cycle retries with the same keyID.
            if let dcError = error as? DCError {
                switch dcError.code {
                case .invalidInput,
                     .invalidKey:
                    keychain.removeObject(forKey: Self.keyIDStorageKey)
                    let reason = dcError.code == .invalidKey ? "invalidKey" : "invalidInput"
                    debug(.telemetry, "attestKey \(reason): discarded keyID; will regenerate next cycle")
                case .serverUnavailable:
                    debug(.telemetry, "attestKey serverUnavailable: Apple App Attest backend transient — will retry next cycle")
                default:
                    break
                }
            }
            debug(.telemetry, "attestKey failed: \(error.localizedDescription)")
            throw AttestError.attestationFailed(error)
        }

        guard let appID = Self.currentAppID() else {
            throw AttestError.unknownAppID
        }

        let body: [String: Any] = [
            "attestation": attestationCBOR.base64EncodedString(),
            "key_id": keyID,
            "challenge": challenge,
            "app_id": appID
        ]

        guard let registerURL = Self.requestURL(
            baseURL: baseURL,
            path: "api/attest/register",
            reason: context.reason,
            lastFailureReason: context.lastFailureReason
        ) else { throw AttestError.invalidRequestURL }

        var request = URLRequest(url: registerURL)
        request.httpMethod = "POST"
        context.applyHeaders(to: &request)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 15

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AttestError.transportError
        }

        switch http.statusCode {
        case 200,
             201:
            keychain.setValue(true, forKey: Self.registeredStorageKey)
            debug(.telemetry, "register ok status=\(http.statusCode)")
        case 403:
            // app_id rejected. Sticky — flag the install and surface to caller.
            PropertyPersistentFlags.shared.telemetryAttestForbidden = true
            debug(.telemetry, "register forbidden — app_id=\(appID) rejected; no further attempts")
            throw AttestError.forbidden
        case 400 ..< 500:
            throw AttestError.clientError(http.statusCode)
        case 500 ..< 600:
            throw AttestError.serverError(http.statusCode)
        default:
            throw AttestError.serverError(http.statusCode)
        }
    }

    /// Clears the local App Attest state so the next `registerIfNeeded`
    /// generates a fresh key and re-runs the handshake from scratch. Both the
    /// keyID and the "registered" flag are dropped: `attestKey` may be called
    /// at most once per key per device, so reusing the old keyID would throw
    /// `DCError.invalidKey`. Use when `/checkin` returns 401 (server lost our
    /// registration).
    func invalidateRegistration() {
        injectIfNeeded()
        keychain.removeObject(forKey: Self.keyIDStorageKey)
        keychain.removeObject(forKey: Self.registeredStorageKey)
    }

    /// Full local-state reset for stuck installs. In addition to what
    /// `invalidateRegistration` clears, this also drops the sticky
    /// `telemetryAttestForbidden` flag — so a tester who got 403'd and wants
    /// to retry can do so without reinstalling. Exposed through a button in
    /// the telemetry inspector. Does not touch consent or installId.
    func resetAttestState() {
        injectIfNeeded()
        keychain.removeObject(forKey: Self.keyIDStorageKey)
        keychain.removeObject(forKey: Self.registeredStorageKey)
        PropertyPersistentFlags.shared.telemetryAttestForbidden = false
        debug(.telemetry, "reset App Attest state: keyID, registered flag, and forbidden flag cleared")
    }

    // MARK: - Per-ping assertion

    /// Builds the App Attest assertion for a single `/checkin` send.
    ///
    /// `clientDataHash` for the assertion is `SHA256(payloadBytes || challengeBytes)`.
    /// **Order matters**: payload first, then the challenge (per the server
    /// spec). Returns the base64-encoded assertion CBOR, the keyID (already a
    /// base64url string), and the challenge string — all three become headers
    /// on the outgoing request.
    func assertion(
        forPayload payload: Data,
        baseURL: URL,
        context: TelemetryRequestContext
    ) async throws -> (assertion: String, keyID: String, challenge: String) {
        injectIfNeeded()

        guard isSupported else { throw AttestError.unsupportedDevice }
        guard !isForbidden else { throw AttestError.forbidden }

        let keyID = try await currentOrCreateKeyID()
        let challenge = try await fetchChallenge(
            baseURL: baseURL,
            context: context
        )

        var hasher = SHA256()
        hasher.update(data: payload)
        hasher.update(data: Data(challenge.utf8))
        let clientDataHash = Data(hasher.finalize())

        let assertionCBOR: Data
        do {
            assertionCBOR = try await service.generateAssertion(keyID, clientDataHash: clientDataHash)
        } catch {
            throw AttestError.assertionFailed(error)
        }
        return (assertionCBOR.base64EncodedString(), keyID, challenge)
    }

    // MARK: - Helpers

    /// Reads the cached App Attest key identifier from Keychain, generating a
    /// new one (and persisting it) on first call. The keyID is the only thing
    /// we store — Apple holds the actual private key in the Secure Enclave.
    private func currentOrCreateKeyID() async throws -> String {
        if let cached = keychain.getValue(String.self, forKey: Self.keyIDStorageKey),
           !cached.isEmpty
        {
            return cached
        }
        let newKey: String
        do {
            newKey = try await service.generateKey()
        } catch {
            throw AttestError.keyGenerationFailed(error)
        }
        keychain.setValue(newKey, forKey: Self.keyIDStorageKey)
        debug(.telemetry, "generated new App Attest keyID")
        return newKey
    }

    private func fetchChallenge(baseURL: URL, context: TelemetryRequestContext) async throws -> String {
        guard let challengeURL = Self.requestURL(
            baseURL: baseURL,
            path: "api/auth/ios/challenge",
            reason: context.reason,
            lastFailureReason: context.lastFailureReason
        ) else { throw AttestError.invalidRequestURL }

        var request = URLRequest(url: challengeURL)
        request.httpMethod = "POST"
        context.applyHeaders(to: &request)
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AttestError.transportError
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            if (500 ..< 600).contains(http.statusCode) {
                throw AttestError.serverError(http.statusCode)
            }
            throw AttestError.clientError(http.statusCode)
        }

        struct ChallengeResponse: Decodable { let challenge: String }
        do {
            let cr = try JSONDecoder().decode(ChallengeResponse.self, from: data)
            return cr.challenge
        } catch {
            throw AttestError.malformedResponse
        }
    }

    /// Produces the signed `<TEAMID>.<bundle-id>` application identifier.
    /// Bundle identifiers are intentionally not restricted to Trio's usual
    /// naming convention because forks and alternate distributions may use a
    /// different reverse-DNS identifier.
    ///
    /// Uses Trio's build-expanded `TeamID` Info.plist value first. This remains
    /// available in distribution packages where `embedded.mobileprovision` may
    /// be absent or use a representation our fallback parser cannot scan.
    static func currentAppID() -> String? {
        if let teamID = Bundle.main.object(forInfoDictionaryKey: "TeamID") as? String,
           let bundleID = Bundle.main.bundleIdentifier,
           let appID = appID(teamID: teamID, bundleID: bundleID)
        {
            return appID
        }

        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let raw = try? Data(contentsOf: url),
              let bundleID = Bundle.main.bundleIdentifier
        else { return nil }

        return appID(fromProvisioningProfile: raw, bundleID: bundleID)
    }

    static func appID(teamID: String, bundleID: String) -> String? {
        let teamID = teamID.trimmingCharacters(in: .whitespacesAndNewlines)
        let bundleID = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = "\(teamID).\(bundleID)"
        return isValidAppID(candidate) ? candidate : nil
    }

    static func appID(fromProvisioningProfile data: Data, bundleID: String) -> String? {
        guard let plist = provisioningPlist(from: data),
              let entitlements = plist["Entitlements"] as? [String: Any]
        else { return nil }

        for key in ["application-identifier", "com.apple.application-identifier"] {
            if let candidate = entitlements[key] as? String, isValidAppID(candidate) {
                return candidate
            }
        }

        let teamIDs = [
            entitlements["com.apple.developer.team-identifier"] as? String,
            (plist["TeamIdentifier"] as? [String])?.first,
            (plist["ApplicationIdentifierPrefix"] as? [String])?.first
        ]
        for teamID in teamIDs.compactMap({ $0 }) {
            if let candidate = appID(teamID: teamID, bundleID: bundleID) {
                return candidate
            }
        }
        return nil
    }

    private static func provisioningPlist(from data: Data) -> [String: Any]? {
        if let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
           let dictionary = plist as? [String: Any]
        {
            return dictionary
        }

        // A mobile provision is a CMS envelope containing an XML plist. Search
        // the bytes directly so arbitrary binary CMS bytes are never decoded as
        // text and cannot corrupt the plist's Unicode contents.
        let xmlProlog = data.range(of: Data("<?xml".utf8))
        let plistTag = data.range(of: Data("<plist".utf8))
        let plistEnd = Data("</plist>".utf8)
        guard let start = xmlProlog ?? plistTag,
              let end = data.range(of: plistEnd, in: start.lowerBound ..< data.endIndex)
        else { return nil }

        let plistData = data[start.lowerBound ..< end.upperBound]
        guard let plist = try? PropertyListSerialization.propertyList(
            from: Data(plistData),
            options: [],
            format: nil
        ) else { return nil }
        return plist as? [String: Any]
    }

    private static func isValidAppID(_ appID: String) -> Bool {
        let parts = appID.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2, !parts[0].isEmpty else { return false }

        let teamIDIsValid = parts[0].allSatisfy { $0.isASCII && ($0.isUppercase || $0.isNumber) }
        let bundleIDIsValid = parts.dropFirst().allSatisfy { component in
            !component.isEmpty && component.allSatisfy {
                $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-")
            }
        }
        return teamIDIsValid && bundleIDIsValid
    }

    static func requestURL(
        baseURL: URL,
        path: String,
        reason: String,
        lastFailureReason: String?
    ) -> URL? {
        guard var components = URLComponents(
            url: baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        ) else { return nil }

        var queryItems = components.queryItems ?? []
        queryItems.append(URLQueryItem(name: "reason", value: reason))
        if let lastFailureReason, !lastFailureReason.isEmpty {
            queryItems.append(URLQueryItem(name: "lastFailureReason", value: lastFailureReason))
        }
        components.queryItems = queryItems
        return components.url
    }

    // MARK: - Errors

    enum AttestError: Error, CustomStringConvertible {
        case unsupportedDevice
        case forbidden
        case unknownAppID
        case keyGenerationFailed(Error)
        case attestationFailed(Error)
        case assertionFailed(Error)
        case transportError
        case malformedResponse
        case invalidRequestURL
        case clientError(Int)
        case serverError(Int)

        var description: String {
            switch self {
            case .unsupportedDevice: return "App Attest unsupported on this device"
            case .forbidden: return "app_id forbidden by server"
            case .unknownAppID: return "unable to read application-identifier entitlement"
            case let .keyGenerationFailed(e): return "generateKey failed: \(e.localizedDescription)"
            case let .attestationFailed(e): return "attestKey failed: \(e.localizedDescription)"
            case let .assertionFailed(e): return "generateAssertion failed: \(e.localizedDescription)"
            case .transportError: return "non-HTTP response"
            case .malformedResponse: return "malformed challenge response"
            case .invalidRequestURL: return "unable to construct telemetry request URL"
            case let .clientError(code): return "client error \(code)"
            case let .serverError(code): return "server error \(code)"
            }
        }
    }
}
