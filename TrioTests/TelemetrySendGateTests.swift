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
            minimumInterval: interval
        ) { true }

        #expect(sent)
    }

    @Test("Background wake does nothing before 24 hours") func recentBackgroundWakeDoesNotSend() async {
        let gate = TelemetrySendGate()
        let sent = await gate.runIfEligible(
            now: now,
            lastSentAt: now.addingTimeInterval(-interval + 1),
            minimumInterval: interval
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
                    await gate.runIfEligible(now: testNow, lastSentAt: nil, minimumInterval: testInterval) {
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

        let sent = await gate.runIfEligible(now: now, lastSentAt: nil, minimumInterval: interval) {
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

        let sent = await gate.runIfEligible(now: now, lastSentAt: nil, minimumInterval: interval) {
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
