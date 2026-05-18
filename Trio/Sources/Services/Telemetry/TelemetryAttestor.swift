import CryptoKit
import DeviceCheck
import Foundation
import Swinject

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
    /// performs `generateKey` → fetch challenge → `attestKey` → POST register.
    /// Throws on transport / server errors; sets the sticky "forbidden" flag
    /// on a 403 so future cycles short-circuit.
    func registerIfNeeded(baseURL: URL) async throws {
        injectIfNeeded()

        guard isSupported else { throw AttestError.unsupportedDevice }
        guard !isForbidden else { throw AttestError.forbidden }

        if (keychain.getValue(Bool.self, forKey: Self.registeredStorageKey) ?? false) == true {
            return
        }

        // generateKey() returns a base64url-encoded key identifier (Apple's docs).
        // We persist it as-is for use in the assertion path below.
        let keyID = try await currentOrCreateKeyID()
        let challenge = try await fetchChallenge(baseURL: baseURL)

        // App Attest expects a SHA-256 of the "client data" — for the
        // attestation step, that's the challenge bytes alone.
        let challengeBytes = Data(challenge.utf8)
        let clientDataHash = Data(SHA256.hash(data: challengeBytes))

        let attestationCBOR: Data
        do {
            attestationCBOR = try await service.attestKey(keyID, clientDataHash: clientDataHash)
        } catch {
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

        var request = URLRequest(url: baseURL.appendingPathComponent("api/attest/register"))
        request.httpMethod = "POST"
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

    // MARK: - Per-ping assertion

    /// Builds the App Attest assertion for a single `/checkin` send.
    ///
    /// `clientDataHash` for the assertion is `SHA256(payloadBytes || challengeBytes)`.
    /// **Order matters**: payload first, then the challenge (per the server
    /// spec). Returns the base64-encoded assertion CBOR, the keyID (already a
    /// base64url string), and the challenge string — all three become headers
    /// on the outgoing request.
    func assertion(forPayload payload: Data, baseURL: URL) async throws -> (assertion: String, keyID: String, challenge: String) {
        injectIfNeeded()

        guard isSupported else { throw AttestError.unsupportedDevice }
        guard !isForbidden else { throw AttestError.forbidden }

        let keyID = try await currentOrCreateKeyID()
        let challenge = try await fetchChallenge(baseURL: baseURL)

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

    private func fetchChallenge(baseURL: URL) async throws -> String {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/auth/ios/challenge"))
        request.httpMethod = "POST"
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

    /// Produces the `<TEAMID>.<bundle-id>` string the server expects in
    /// `app_id` — matches the regex `^[A-Z0-9]+\.org\.nightscout\.[^.]+\.trio$`
    /// when the build is configured correctly.
    ///
    /// Reads `application-identifier` from `embedded.mobileprovision`. On iOS
    /// the SDK doesn't expose `SecTaskCopyValueForEntitlement` to Swift, and
    /// parsing the mobile-provision file is the standard workaround. Returns
    /// nil for App Store builds (no embedded.mobileprovision) — which Trio
    /// doesn't ship, so this path is fine for sideload + TestFlight.
    static func currentAppID() -> String? {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let raw = try? Data(contentsOf: url)
        else { return nil }

        // The mobileprovision file is a CMS-signed envelope around a plist.
        // Pull the plist substring between the XML prolog and `</plist>`.
        // ISO Latin-1 maps every byte 0x00–0xFF 1:1, so the conversion never
        // fails on the binary CMS bytes surrounding the plist — `.ascii` would
        // return nil here.
        guard let scanned = String(data: raw, encoding: .isoLatin1),
              let start = scanned.range(of: "<?xml"),
              let end = scanned.range(of: "</plist>")
        else { return nil }

        let plistString = String(scanned[start.lowerBound ..< end.upperBound])
        guard let plistData = plistString.data(using: .utf8),
              let plist = try? PropertyListSerialization
              .propertyList(from: plistData, options: [], format: nil) as? [String: Any],
              let entitlements = plist["Entitlements"] as? [String: Any],
              let appID = entitlements["application-identifier"] as? String
        else { return nil }

        return appID
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
            case let .clientError(code): return "client error \(code)"
            case let .serverError(code): return "server error \(code)"
            }
        }
    }
}
