import Foundation
import Testing

@testable import Trio

@Suite("Telemetry Send Gate Tests") struct TelemetrySendGateTests {
    private let interval: TimeInterval = 24 * 60 * 60
    private let now = Date(timeIntervalSince1970: 2_000_000)

    @Test("Background wake sends when more than 24 hours overdue") func overdueBackgroundWakeSends() async {
        let gate = TelemetrySendGate()
        let sent = await gate.runIfEligible(
            now: now,
            lastSentAt: now.addingTimeInterval(-interval - 1),
            lastAttemptAt: nil,
            minimumInterval: interval,
            retryInterval: 60 * 60
        ) { true }

        #expect(sent)
    }

    @Test("Background wake does nothing before 24 hours") func recentBackgroundWakeDoesNotSend() async {
        let gate = TelemetrySendGate()
        let sent = await gate.runIfEligible(
            now: now,
            lastSentAt: now.addingTimeInterval(-interval + 1),
            lastAttemptAt: nil,
            minimumInterval: interval,
            retryInterval: 60 * 60
        ) { true }

        #expect(!sent)
    }

    @Test("Failed attempt backs off for one hour") func recentFailureBacksOff() async {
        let gate = TelemetrySendGate()
        let sent = await gate.runIfEligible(
            now: now,
            lastSentAt: nil,
            lastAttemptAt: now.addingTimeInterval(-(60 * 60) + 1),
            minimumInterval: interval,
            retryInterval: 60 * 60
        ) { true }

        #expect(!sent)
    }

    @Test("Forced sends still honor failure backoff") func forcedSendHonorsBackoff() async {
        let gate = TelemetrySendGate()
        let sent = await gate.runIfEligible(
            now: now,
            lastSentAt: now,
            lastAttemptAt: now,
            minimumInterval: interval,
            retryInterval: 60 * 60,
            force: true
        ) { true }

        #expect(!sent)
    }

    @Test("Concurrent triggers produce one send") func concurrentTriggersProduceOneSend() async {
        let gate = TelemetrySendGate()
        let attempts = AttemptCounter()
        let testNow = now
        let testInterval = interval

        await withTaskGroup(of: Bool.self) { group in
            for _ in 0 ..< 8 {
                group.addTask {
                    await gate.runIfEligible(
                        now: testNow,
                        lastSentAt: nil,
                        lastAttemptAt: nil,
                        minimumInterval: testInterval,
                        retryInterval: 60 * 60
                    ) {
                        await attempts.increment()
                        try? await Task.sleep(for: .milliseconds(50))
                        return true
                    }
                }
            }

            var results: [Bool] = []
            for await result in group { results.append(result) }
            #expect(results.filter { $0 }.count == 1)
        }

        #expect(await attempts.value == 1)
    }

    @Test("Failed sends do not advance last-sent state") func failedSendDoesNotAdvanceTimestamp() async {
        let gate = TelemetrySendGate()
        let state = SuccessState()

        let sent = await gate.runIfEligible(
            now: now,
            lastSentAt: nil,
            lastAttemptAt: nil,
            minimumInterval: interval,
            retryInterval: 60 * 60
        ) {
            false
        } onSuccess: {
            state.record()
        }

        #expect(!sent)
        #expect(state.timestamp == nil)
    }

    @Test("Successful sends advance last-sent state") func successfulSendAdvancesTimestamp() async {
        let gate = TelemetrySendGate()
        let state = SuccessState()

        let sent = await gate.runIfEligible(
            now: now,
            lastSentAt: nil,
            lastAttemptAt: nil,
            minimumInterval: interval,
            retryInterval: 60 * 60
        ) {
            true
        } onSuccess: {
            state.record()
        }

        #expect(sent)
        #expect(state.timestamp != nil)
    }

    @Test("Check-in URL includes its trigger reason") func checkinURLIncludesReason() throws {
        let url = try #require(
            TelemetryClient.checkinURL(
                baseURL: URL(string: "https://telemetry.example/api")!,
                reason: .backgroundActivity,
                lastFailureReason: nil
            )
        )
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))

        #expect(components.path == "/api/checkin")
        #expect(components.queryItems == [URLQueryItem(name: "reason", value: "background_activity")])
    }

    @Test("Check-in URL reports the prior failure") func checkinURLIncludesPriorFailure() throws {
        let url = try #require(
            TelemetryClient.checkinURL(
                baseURL: URL(string: "https://telemetry.example")!,
                reason: .foreground,
                lastFailureReason: "request_failed"
            )
        )
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))

        #expect(components.queryItems?.contains(URLQueryItem(name: "reason", value: "foreground")) == true)
        #expect(components.queryItems?.contains(URLQueryItem(name: "lastFailureReason", value: "request_failed")) == true)
    }

    @Test("Application ID derives from build team and bundle IDs") func derivesApplicationID() {
        #expect(
            TelemetryAttestor.appID(teamID: " ABC123 ", bundleID: "org.nightscout.user.trio") ==
                "ABC123.org.nightscout.user.trio"
        )
        #expect(
            TelemetryAttestor.appID(teamID: "ABC123", bundleID: "com.example.custom-fork") ==
                "ABC123.com.example.custom-fork"
        )
        #expect(TelemetryAttestor.appID(teamID: "$(DEVELOPMENT_TEAM)", bundleID: "org.example.trio") == nil)
        #expect(TelemetryAttestor.appID(teamID: "ABC123", bundleID: "com..example") == nil)
    }

    @Test("Provisioning profile returns the first valid application ID") func parsesProvisioningApplicationID() throws {
        let profile: [String: Any] = [
            "Entitlements": [
                "application-identifier": "invalid",
                "com.apple.application-identifier": "ABC123.org.nightscout.user.trio"
            ]
        ]
        let plist = try PropertyListSerialization.data(fromPropertyList: profile, format: .xml, options: 0)
        var cmsEnvelope = Data([0x00, 0xFF, 0x80, 0x01])
        cmsEnvelope.append(plist)
        cmsEnvelope.append(Data([0xFE, 0x00]))

        #expect(
            TelemetryAttestor.appID(
                fromProvisioningProfile: cmsEnvelope,
                bundleID: "org.nightscout.fallback.trio"
            ) == "ABC123.org.nightscout.user.trio"
        )
    }

    @Test("Provisioning profile derives app ID from signed team ID") func derivesProvisioningApplicationID() throws {
        let profile: [String: Any] = [
            "Entitlements": ["com.apple.developer.team-identifier": "TEAM123"],
            "TeamIdentifier": ["OTHERTEAM"]
        ]
        let plist = try PropertyListSerialization.data(fromPropertyList: profile, format: .binary, options: 0)

        #expect(
            TelemetryAttestor.appID(
                fromProvisioningProfile: plist,
                bundleID: "org.nightscout.owner.trio"
            ) == "TEAM123.org.nightscout.owner.trio"
        )
    }

    @Test("Malformed provisioning profiles safely return nil") func malformedProvisioningProfileReturnsNil() {
        let malformedInputs = [Data(), Data([0x00, 0xFF, 0x01]), Data("<?xml broken </plist>".utf8)]

        for data in malformedInputs {
            #expect(
                TelemetryAttestor.appID(
                    fromProvisioningProfile: data,
                    bundleID: "org.nightscout.owner.trio"
                ) == nil
            )
        }
    }

    @Test("Attestation endpoints include reason and prior failure") func attestationURLsIncludeTelemetryContext() throws {
        for path in ["api/auth/ios/challenge", "api/attest/register"] {
            let url = try #require(
                TelemetryAttestor.requestURL(
                    baseURL: URL(string: "https://telemetry.example")!,
                    path: path,
                    reason: "background_activity",
                    lastFailureReason: "registration_failed"
                )
            )
            let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))

            #expect(components.path == "/\(path)")
            #expect(components.queryItems?.contains(URLQueryItem(name: "reason", value: "background_activity")) == true)
            #expect(
                components.queryItems?.contains(URLQueryItem(name: "lastFailureReason", value: "registration_failed")) == true
            )
        }
    }

    @Test("Telemetry context adds version and install headers") func telemetryContextHeaders() throws {
        let context = TelemetryRequestContext(
            reason: "background_activity",
            lastFailureReason: "registration_failed",
            trioVersion: "0.8.1",
            installID: "install-123"
        )
        var request = URLRequest(url: URL(string: "https://telemetry.example/checkin")!)

        context.applyHeaders(to: &request)

        #expect(request.value(forHTTPHeaderField: "X-Trio-Version") == "0.8.1")
        #expect(request.value(forHTTPHeaderField: "X-Trio-InstallId") == "install-123")
    }
}

private actor AttemptCounter {
    private(set) var value = 0

    func increment() {
        value += 1
    }
}

private final class SuccessState: @unchecked Sendable {
    private let lock = NSLock()
    private var storedTimestamp: Date?

    var timestamp: Date? {
        lock.withLock { storedTimestamp }
    }

    func record() {
        lock.withLock { storedTimestamp = Date() }
    }
}
