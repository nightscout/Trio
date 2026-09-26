import Foundation
import Testing

@testable import Trio

@Suite("Watch Command Request Cache Tests") struct WatchCommandRequestCacheTests {
    let appUUID = UUID()
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let done = WatchCommandResult.success(.overrideStopped, "Override stopped.")

    private func key(_ requestID: UUID = UUID(), app: UUID? = nil) -> WatchCommandRequestCache.Key {
        WatchCommandRequestCache.Key(appUUID: app ?? appUUID, requestID: requestID)
    }

    private func ticket(_ admission: WatchCommandRequestCache.Admission) -> WatchCommandRequestCache.Ticket? {
        guard case let .accepted(ticket) = admission else { return nil }
        return ticket
    }

    private func admitted(
        _ cache: WatchCommandRequestCache,
        _ key: WatchCommandRequestCache.Key,
        _ command: WatchCommand,
        at now: Date
    ) async throws -> WatchCommandRequestCache.Ticket {
        let admission = await cache.admit(key, command: command, now: now)
        return try #require(ticket(admission))
    }

    @Test("A request stays in flight until completed, then replays its result") func testInFlightThenCompleted() async throws {
        let cache = WatchCommandRequestCache()
        let key = key()
        let result = WatchCommandResult.success(.carbsLogged, "Carbs logged.")

        let reservation = try await admitted(cache, key, .carbs(20), at: start)
        #expect(await cache.admit(key, command: .carbs(20), now: start) == .inProgress)

        await cache.complete(reservation, result: result)
        #expect(await cache.admit(key, command: .carbs(20), now: start) == .completed(result))
    }

    @Test("Reusing a request ID for another command is a conflict") func testConflict() async throws {
        let cache = WatchCommandRequestCache()
        let key = key()

        _ = try await admitted(cache, key, .carbs(20), at: start)
        #expect(await cache.admit(key, command: .carbs(25), now: start) == .conflict)
        #expect(await cache.admit(key, command: .cancelOverride, now: start) == .conflict)
    }

    @Test("The same request ID from another app is a separate request") func testScopedByApp() async {
        let cache = WatchCommandRequestCache()
        let requestID = UUID()

        #expect(ticket(await cache.admit(key(requestID), command: .cancelOverride, now: start)) != nil)
        #expect(ticket(await cache.admit(key(requestID, app: UUID()), command: .cancelOverride, now: start)) != nil)
    }

    @Test("Completed entries expire after their lifetime") func testExpiry() async throws {
        let cache = WatchCommandRequestCache(capacity: 256, lifetime: 15 * 60)
        let key = key()

        let reservation = try await admitted(cache, key, .cancelOverride, at: start)
        await cache.complete(reservation, result: done)
        #expect(await cache.admit(key, command: .cancelOverride, now: start.addingTimeInterval(15 * 60 - 1)) == .completed(done))
        #expect(ticket(await cache.admit(key, command: .cancelOverride, now: start.addingTimeInterval(15 * 60))) != nil)
    }

    @Test("An executing entry outlives its lifetime") func testInFlightNeverExpires() async throws {
        let cache = WatchCommandRequestCache(capacity: 256, lifetime: 15 * 60)
        let key = key()

        _ = try await admitted(cache, key, .cancelOverride, at: start)
        #expect(await cache.admit(key, command: .cancelOverride, now: start.addingTimeInterval(60 * 60)) == .inProgress)
    }

    @Test("A full cache evicts the least recently used completed entry") func testLeastRecentlyUsedEviction() async throws {
        let cache = WatchCommandRequestCache(capacity: 2, lifetime: 15 * 60)
        let first = key()
        let second = key()

        try await cache.complete(admitted(cache, first, .cancelOverride, at: start), result: done)
        try await cache.complete(admitted(cache, second, .cancelOverride, at: start), result: done)
        // touching the first entry makes the second the least recently used
        #expect(await cache.admit(first, command: .cancelOverride, now: start) == .completed(done))
        #expect(ticket(await cache.admit(key(), command: .cancelOverride, now: start)) != nil)

        #expect(await cache.count == 2)
        #expect(await cache.admit(first, command: .cancelOverride, now: start) == .completed(done))
        #expect(ticket(await cache.admit(second, command: .cancelOverride, now: start)) != nil, "Second was evicted")
    }

    @Test("Executing entries are never evicted; a full cache rejects instead") func testCapacityKeepsInFlight() async throws {
        let cache = WatchCommandRequestCache(capacity: 2, lifetime: 15 * 60)
        let first = key()
        let second = key()

        let firstTicket = try await admitted(cache, first, .bolus(1), at: start)
        _ = try await admitted(cache, second, .bolus(2), at: start)

        #expect(await cache.admit(key(), command: .bolus(3), now: start) == .full)
        // a replay of a running request is still recognized, never re-admitted
        #expect(await cache.admit(first, command: .bolus(1), now: start) == .inProgress)
        #expect(await cache.admit(first, command: .bolus(5), now: start) == .conflict)

        await cache.complete(firstTicket, result: done)
        #expect(ticket(await cache.admit(key(), command: .bolus(3), now: start)) != nil, "A completed slot frees up")
        #expect(await cache.admit(second, command: .bolus(2), now: start) == .inProgress)
    }

    @Test("A stale execution cannot complete a newer admission of the same key") func testStaleCompletion() async throws {
        let cache = WatchCommandRequestCache(capacity: 256, lifetime: 15 * 60)
        let key = key()
        let stale = WatchCommandResult.failure("stale")
        let fresh = WatchCommandResult.success(.carbsLogged, "fresh")

        let oldTicket = try await admitted(cache, key, .carbs(10), at: start)
        await cache.complete(oldTicket, result: stale)
        let later = start.addingTimeInterval(15 * 60)
        let newTicket = try await admitted(cache, key, .carbs(10), at: later)
        #expect(newTicket != oldTicket)

        await cache.complete(oldTicket, result: stale)
        #expect(await cache.admit(key, command: .carbs(10), now: later) == .inProgress)

        await cache.complete(newTicket, result: fresh)
        #expect(await cache.admit(key, command: .carbs(10), now: later) == .completed(fresh))
        await cache.complete(oldTicket, result: stale)
        #expect(await cache.admit(key, command: .carbs(10), now: later) == .completed(fresh), "Completed results are final")
    }

    @Test("Expired entries are evicted before live ones") func testExpiredEvictedFirst() async throws {
        let cache = WatchCommandRequestCache(capacity: 2, lifetime: 15 * 60)
        let old = key()
        let recent = key()

        try await cache.complete(admitted(cache, old, .cancelOverride, at: start), result: done)
        _ = await cache.admit(recent, command: .cancelOverride, now: start.addingTimeInterval(10 * 60))
        #expect(ticket(await cache.admit(key(), command: .cancelOverride, now: start.addingTimeInterval(16 * 60))) != nil)

        #expect(await cache.admit(recent, command: .cancelOverride, now: start.addingTimeInterval(16 * 60)) == .inProgress)
    }

    @Test("Default limits are 256 entries for 15 minutes") func testDefaults() {
        #expect(WatchCommandRequestCache.defaultCapacity == 256)
        #expect(WatchCommandRequestCache.defaultLifetime == 15 * 60)
    }
}
