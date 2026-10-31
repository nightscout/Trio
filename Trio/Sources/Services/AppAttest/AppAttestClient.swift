import CryptoKit
import DeviceCheck
import Foundation

protocol AppAttestService {
    var isSupported: Bool { get }
    func generateKey() async throws -> String
    func attestKey(_ keyId: String, clientDataHash: Data) async throws -> Data
    func generateAssertion(_ keyId: String, clientDataHash: Data) async throws -> Data
}

extension DCAppAttestService: AppAttestService {}

struct AppAttestClient {
    struct Assertion: Equatable {
        let keyID: String
        let assertion: String
        let challenge: String
    }

    let baseURL: URL
    let challengePath: String
    let registerPath: String
    // Keychain keys are "<namespace>.keyID" and "<namespace>.registered"
    let namespace: String
    let keychain: Keychain
    let category: Logger.Category
    var registerFields = (keyID: "keyId", appID: "appId")
    var challengeBody: Data?
    var queryItems: [URLQueryItem] = []
    var prepare: (inout URLRequest) -> Void = { _ in }
    var timeout: TimeInterval = 15
    var timeoutRetries = 0
    var service: AppAttestService = DCAppAttestService.shared
    var session: URLSession = .shared
    var appID: () -> String? = AppAttestClient.currentAppID

    var isSupported: Bool {
        service.isSupported
    }

    var isRegistered: Bool {
        keychain.getValue(Bool.self, forKey: Self.registeredKey(namespace)) ?? false
    }

    func registerIfNeeded() async throws {
        guard isSupported else { throw AttestError.unsupportedDevice }
        guard !isRegistered else { return }

        let keyID = try await currentOrCreateKeyID()
        let challenge = try await fetchChallenge()
        let clientDataHash = Data(SHA256.hash(data: Data(challenge.utf8)))

        debug(
            category,
            "Attesting key \(keyID.prefix(8)) (\(keyID.count) chars), supported \(service.isSupported), hash \(clientDataHash.count) bytes, challenge \(challenge.count) chars, bundle \(Bundle.main.bundleIdentifier ?? "unknown")"
        )

        let attestation: Data
        do {
            attestation = try await service.attestKey(keyID, clientDataHash: clientDataHash)
        } catch {
            // attestKey works once per key; invalidKey and invalidInput (a key left over from a reinstall) mean a new key
            if let dcError = error as? DCError {
                switch dcError.code {
                case .invalidInput,
                     .invalidKey:
                    keychain.removeObject(forKey: Self.keyIDKey(namespace))
                    let reason = dcError.code == .invalidKey ? "invalidKey" : "invalidInput"
                    debug(category, "App Attest key rejected (\(reason)), discarding it")
                case .serverUnavailable:
                    debug(category, "App Attest server unavailable, retrying next time")
                default:
                    break
                }
            }
            debug(category, "App Attest key attestation failed")
            throw AttestError.attestationFailed(error)
        }

        guard let appID = appID() else { throw AttestError.unknownAppID }

        let body: [String: Any] = [
            "attestation": attestation.base64EncodedString(),
            registerFields.keyID: keyID,
            "challenge": challenge,
            registerFields.appID: appID
        ]
        var request = try makeRequest(path: registerPath)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await session.data(for: request, timeoutRetries: timeoutRetries, category: category)
        guard let http = response as? HTTPURLResponse else { throw AttestError.transportError }

        switch http.statusCode {
        case 200,
             201:
            keychain.setValue(true, forKey: Self.registeredKey(namespace))
            info(category, "Registered App Attest key with the server")
        case 403:
            throw AttestError.forbidden
        case 400 ..< 500:
            throw AttestError.clientError(http.statusCode)
        default:
            throw AttestError.serverError(http.statusCode)
        }
    }

    // Signs SHA256(payload ‖ challenge) with a fresh challenge
    func assertion(for payload: Data) async throws -> Assertion {
        guard isSupported else { throw AttestError.unsupportedDevice }

        let keyID = try await currentOrCreateKeyID()
        let challenge = try await fetchChallenge()

        var hasher = SHA256()
        hasher.update(data: payload)
        hasher.update(data: Data(challenge.utf8))
        let clientDataHash = Data(hasher.finalize())

        let assertion: Data
        do {
            assertion = try await service.generateAssertion(keyID, clientDataHash: clientDataHash)
        } catch {
            throw AttestError.assertionFailed(error)
        }
        return Assertion(keyID: keyID, assertion: assertion.base64EncodedString(), challenge: challenge)
    }

    // Drops both the key and the registered flag: attestKey can't run twice on the same key
    func invalidateRegistration() {
        Self.invalidateRegistration(namespace: namespace, in: keychain)
    }

    static func invalidateRegistration(namespace: String, in keychain: Keychain) {
        keychain.removeObject(forKey: keyIDKey(namespace))
        keychain.removeObject(forKey: registeredKey(namespace))
    }

    static func keyIDKey(_ namespace: String) -> String {
        "\(namespace).keyID"
    }

    static func registeredKey(_ namespace: String) -> String {
        "\(namespace).registered"
    }

    private func currentOrCreateKeyID() async throws -> String {
        if let cached = keychain.getValue(String.self, forKey: Self.keyIDKey(namespace)), !cached.isEmpty {
            return cached
        }
        let keyID: String
        do {
            keyID = try await service.generateKey()
        } catch {
            throw AttestError.keyGenerationFailed(error)
        }
        keychain.setValue(keyID, forKey: Self.keyIDKey(namespace))
        debug(category, "Generated new App Attest key")
        return keyID
    }

    private func fetchChallenge() async throws -> String {
        var request = try makeRequest(path: challengePath)
        if let challengeBody {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = challengeBody
        }

        let (data, response) = try await session.data(for: request, timeoutRetries: timeoutRetries, category: category)
        guard let http = response as? HTTPURLResponse else { throw AttestError.transportError }
        guard (200 ..< 300).contains(http.statusCode) else {
            if (500 ..< 600).contains(http.statusCode) {
                throw AttestError.serverError(http.statusCode)
            }
            throw AttestError.clientError(http.statusCode)
        }

        struct Reply: Decodable { let challenge: String }
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data) else {
            throw AttestError.malformedResponse
        }
        return reply.challenge
    }

    private func makeRequest(path: String) throws -> URLRequest {
        guard let url = Self.requestURL(baseURL: baseURL, path: path, queryItems: queryItems) else {
            throw AttestError.invalidRequestURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        prepare(&request)
        request.timeoutInterval = timeout
        return request
    }

    static func requestURL(baseURL: URL, path: String, queryItems: [URLQueryItem]) -> URL? {
        guard var components = URLComponents(
            url: baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        ) else { return nil }
        if !queryItems.isEmpty {
            components.queryItems = (components.queryItems ?? []) + queryItems
        }
        return components.url
    }

    // MARK: - App ID

    // "<TeamID>.<bundle ID>"; the build-expanded TeamID comes first because distribution builds may lack a provisioning profile
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

        // A provisioning profile is a CMS envelope around an XML plist; search the bytes so CMS data is never decoded as text
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
            case .invalidRequestURL: return "unable to construct request URL"
            case let .clientError(code): return "client error \(code)"
            case let .serverError(code): return "server error \(code)"
            }
        }
    }
}

extension URLSession {
    // A server that scales to zero can time out on its first request
    func data(for request: URLRequest, timeoutRetries: Int, category: Logger.Category) async throws -> (Data, URLResponse) {
        var retries = timeoutRetries
        while true {
            do {
                return try await data(for: request)
            } catch let error as URLError where error.code == .timedOut && retries > 0 {
                retries -= 1
                warning(category, "Request to \(request.url?.path ?? "server") timed out, retrying", error: error)
            }
        }
    }
}
