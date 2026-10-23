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

// App Attest for the telemetry uploader; a 403 from register is sticky so later cycles stop trying
final class TelemetryAttestor: Injectable {
    typealias AttestError = AppAttestClient.AttestError

    // Container-scoped singleton; shared is a convenience accessor
    static var shared: TelemetryAttestor { TrioApp.resolver.resolve(TelemetryAttestor.self)! }

    @Injected() private var keychain: Keychain!

    private let service = DCAppAttestService.shared

    private static let namespace = "TelemetryAttest"

    init(resolver: Resolver) {
        injectServices(resolver)
    }

    var isSupported: Bool {
        service.isSupported
    }

    var isForbidden: Bool {
        PropertyPersistentFlags.shared.telemetryAttestForbidden == true
    }

    func registerIfNeeded(baseURL: URL, context: TelemetryRequestContext) async throws {
        guard isSupported else { throw AttestError.unsupportedDevice }
        guard !isForbidden else { throw AttestError.forbidden }

        do {
            try await client(baseURL: baseURL, context: context).registerIfNeeded()
        } catch AttestError.forbidden {
            PropertyPersistentFlags.shared.telemetryAttestForbidden = true
            warning(.telemetry, "Registration rejected with HTTP 403, no further attempts")
            throw AttestError.forbidden
        }
    }

    // Use when /checkin returns 401 (the server lost our registration)
    func invalidateRegistration() {
        AppAttestClient.invalidateRegistration(namespace: Self.namespace, in: keychain)
    }

    // Also clears the sticky 403 flag so testers can retry without reinstalling
    func resetAttestState() {
        AppAttestClient.invalidateRegistration(namespace: Self.namespace, in: keychain)
        PropertyPersistentFlags.shared.telemetryAttestForbidden = false
        info(.telemetry, "App Attest state reset")
    }

    func assertion(
        forPayload payload: Data,
        baseURL: URL,
        context: TelemetryRequestContext
    ) async throws -> (assertion: String, keyID: String, challenge: String) {
        guard isSupported else { throw AttestError.unsupportedDevice }
        guard !isForbidden else { throw AttestError.forbidden }

        let result = try await client(baseURL: baseURL, context: context).assertion(for: payload)
        return (result.assertion, result.keyID, result.challenge)
    }

    private func client(baseURL: URL, context: TelemetryRequestContext) -> AppAttestClient {
        AppAttestClient(
            baseURL: baseURL,
            challengePath: "api/auth/ios/challenge",
            registerPath: "api/attest/register",
            namespace: Self.namespace,
            keychain: keychain,
            category: .telemetry,
            registerFields: (keyID: "key_id", appID: "app_id"),
            queryItems: Self.queryItems(reason: context.reason, lastFailureReason: context.lastFailureReason),
            prepare: { context.applyHeaders(to: &$0) },
            service: service
        )
    }

    static func requestURL(
        baseURL: URL,
        path: String,
        reason: String,
        lastFailureReason: String?
    ) -> URL? {
        AppAttestClient.requestURL(
            baseURL: baseURL,
            path: path,
            queryItems: queryItems(reason: reason, lastFailureReason: lastFailureReason)
        )
    }

    private static func queryItems(reason: String, lastFailureReason: String?) -> [URLQueryItem] {
        var items = [URLQueryItem(name: "reason", value: reason)]
        if let lastFailureReason, !lastFailureReason.isEmpty {
            items.append(URLQueryItem(name: "lastFailureReason", value: lastFailureReason))
        }
        return items
    }
}
