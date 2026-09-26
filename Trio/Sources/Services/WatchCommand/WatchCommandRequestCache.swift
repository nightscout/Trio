import Foundation

/// Remembers recent watch request IDs so a relayed or retried command executes at most once.
///
/// In memory only: after an app restart the freshness window and bolus safety checks are what
/// stop a replay.
actor WatchCommandRequestCache {
    struct Key: Hashable {
        let appUUID: UUID
        let requestID: UUID
    }

    /// Proof of one admission; only its holder may complete the entry it reserved.
    struct Ticket: Equatable {
        let key: Key
        let generation: UInt64
    }

    enum Admission: Equatable {
        /// First sighting; the caller must execute and then call `complete` with the ticket.
        case accepted(Ticket)
        case inProgress
        /// The request ID was already used for a different command.
        case conflict
        case completed(WatchCommandResult)
        /// Every slot holds an executing request, and those are never evicted.
        case full
    }

    private enum State {
        case inFlight(generation: UInt64)
        case completed(WatchCommandResult)
    }

    private struct Entry {
        let command: WatchCommand
        var state: State
        let insertedAt: Date
        var lastUsed: UInt64

        var isInFlight: Bool {
            if case .inFlight = state { return true }
            return false
        }
    }

    static let defaultCapacity = 256
    static let defaultLifetime: TimeInterval = 15 * 60

    private let capacity: Int
    private let lifetime: TimeInterval

    private var entries: [Key: Entry] = [:]
    /// Monotonic use counter; a clock would tie when several requests arrive within one tick.
    private var useCounter: UInt64 = 0
    private var generationCounter: UInt64 = 0

    init(capacity: Int = defaultCapacity, lifetime: TimeInterval = defaultLifetime) {
        self.capacity = capacity
        self.lifetime = lifetime
    }

    var count: Int { entries.count }

    /// Reserves `key` before anything executes, or reports why it must not run now.
    func admit(_ key: Key, command: WatchCommand, now: Date) -> Admission {
        evictExpired(now: now)
        useCounter += 1

        if var entry = entries[key] {
            guard entry.command == command else { return .conflict }
            entry.lastUsed = useCounter
            entries[key] = entry
            switch entry.state {
            case .inFlight: return .inProgress
            case let .completed(result): return .completed(result)
            }
        }

        if entries.count >= capacity {
            // evicting a running request would let its duplicate execute a second time
            guard let leastRecentlyUsed = entries.filter({ !$0.value.isInFlight })
                .min(by: { $0.value.lastUsed < $1.value.lastUsed })?.key
            else { return .full }
            entries[leastRecentlyUsed] = nil
        }

        generationCounter += 1
        let ticket = Ticket(key: key, generation: generationCounter)
        entries[key] = Entry(
            command: command,
            state: .inFlight(generation: ticket.generation),
            insertedAt: now,
            lastUsed: useCounter
        )
        return .accepted(ticket)
    }

    /// Ignored unless `ticket` still owns the reservation, so a stale execution cannot overwrite
    /// the result of a newer admission under the same key.
    func complete(_ ticket: Ticket, result: WatchCommandResult) {
        guard var entry = entries[ticket.key],
              case let .inFlight(generation) = entry.state,
              generation == ticket.generation
        else { return }
        entry.state = .completed(result)
        entries[ticket.key] = entry
    }

    /// Executing entries outlive their lifetime until they complete.
    private func evictExpired(now: Date) {
        entries = entries.filter { $0.value.isInFlight || now.timeIntervalSince($0.value.insertedAt) < lifetime }
    }
}
