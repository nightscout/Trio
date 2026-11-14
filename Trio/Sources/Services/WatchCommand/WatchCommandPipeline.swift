import CoreData
import Foundation

/// Terminal answer to a watch command, sent back to the requesting app only.
struct WatchCommandResult: Equatable {
    let acknowledged: Bool
    let ackCode: BaseWatchManager.AcknowledgmentCode
    /// Short, user-facing text; never carries amounts or internal error details.
    let message: String

    /// Something may have changed on the phone, so the watch needs fresh state.
    var refreshesState: Bool {
        acknowledged
    }

    static func success(_ ackCode: BaseWatchManager.AcknowledgmentCode, _ message: String) -> WatchCommandResult {
        WatchCommandResult(acknowledged: true, ackCode: ackCode, message: message)
    }

    static func failure(_ message: String) -> WatchCommandResult {
        WatchCommandResult(acknowledged: false, ackCode: .genericFailure, message: message)
    }
}

/// Thrown by a final check right before a side effect writes or issues anything; nothing was written.
struct WatchCommandRejection: Error {
    let result: WatchCommandResult
}

/// Revocation epoch for watch commands; a command admitted under an older epoch fails its next check.
final class WatchCommandAuthorization: @unchecked Sendable {
    private let lock = NSLock()
    private var epoch: UInt64 = 0

    var current: UInt64 { lock.withLock { epoch } }

    /// Call on the writing queue before a permission-withdrawing setting is stored; settings
    /// notifications are async and latest-value only, so they miss an off-then-on sequence.
    func revoke() {
        lock.withLock { epoch += 1 }
    }
}

/// Writes watch command log lines at their level and keeps the caller's location; tests replace `write`.
struct WatchCommandLogger: Sendable {
    enum Level: Sendable {
        case debug
        case info
        case warning
    }

    var write: @Sendable(Level, String, String, String, UInt) -> Void

    static let app = WatchCommandLogger { level, message, file, function, line in
        switch level {
        case .debug: Trio.debug(.watch, message, file: file, function: function, line: line)
        case .info: Trio.info(.watch, message, file: file, function: function, line: line)
        case .warning: Trio.warning(.watch, message, file: file, function: function, line: line)
        }
    }

    func debug(_ message: String, file: String = #file, function: String = #function, line: UInt = #line) {
        write(.debug, message, file, function, line)
    }

    func info(_ message: String, file: String = #file, function: String = #function, line: UInt = #line) {
        write(.info, message, file, function, line)
    }

    func warning(_ message: String, file: String = #file, function: String = #function, line: UInt = #line) {
        write(.warning, message, file, function, line)
    }
}

/// The checks an admitted command re-runs at every side-effect boundary.
struct WatchCommandContext: Sendable {
    let issuedAt: Date
    let name: String

    fileprivate let grant: UInt64
    fileprivate let authorization: WatchCommandAuthorization
    fileprivate let gate: @Sendable() -> WatchCommandResult?
    fileprivate let now: @Sendable() -> Date
    fileprivate let log: WatchCommandLogger

    /// Expiry is opt-in after admission: only waits that can outlast the window need it again.
    func rejection(checkingExpiry: Bool = false) -> WatchCommandResult? {
        if checkingExpiry, let expired = expiryRejection() {
            return expired
        }
        guard authorization.current == grant else {
            log.info("Watch \(name) command refused, command settings changed while it was pending")
            return .failure(String(localized: "Watch command settings changed.", comment: "Watch command ack"))
        }
        return gate()
    }

    /// Run synchronously in the side effect's last serialized hop, with nothing awaited before the
    /// write or pump request, so a revocation cannot land between check and effect.
    func finalCheck(checkingExpiry: Bool = false) -> @Sendable() throws -> Void {
        { [self] in
            if let rejection = rejection(checkingExpiry: checkingExpiry) {
                throw WatchCommandRejection(result: rejection)
            }
        }
    }

    private func expiryRejection() -> WatchCommandResult? {
        let age = now().timeIntervalSince(issuedAt)
        guard age <= WatchCommandPipeline.maximumCommandAge, age >= -WatchCommandPipeline.maximumCommandLead else {
            log.info("Watch \(name) command refused, sent outside the 2 minute window")
            return .failure(String(localized: "Command expired. Please try again.", comment: "Watch command ack"))
        }
        return nil
    }
}

/// Runs state-changing watch commands for any transport: at most once per app and request ID,
/// inside a freshness window, and revocable while pending. Transports parse; features execute.
final class WatchCommandPipeline {
    /// Commands arrive within seconds; two minutes only keeps a late or replayed one from running.
    static let maximumCommandAge: TimeInterval = 2 * 60
    /// Clock skew tolerance for watches that run slightly ahead of the phone.
    static let maximumCommandLead: TimeInterval = 60

    private let authorization: WatchCommandAuthorization
    private let cache: WatchCommandRequestCache
    private let now: @Sendable() -> Date
    private let log: WatchCommandLogger

    init(
        authorization: WatchCommandAuthorization,
        cache: WatchCommandRequestCache = WatchCommandRequestCache(),
        now: @escaping @Sendable() -> Date = { Date() },
        log: WatchCommandLogger = .app
    ) {
        self.authorization = authorization
        self.cache = cache
        self.now = now
        self.log = log
    }

    /// `command` identifies the request's content, so a reused request ID is caught; `gate` holds
    /// the feature switches and is re-read with every check.
    func run(
        requestID: UUID,
        appUUID: UUID,
        issuedAt: Date,
        command: AnyHashable,
        name: String,
        gate: @escaping @Sendable() -> WatchCommandResult? = { nil },
        execute: (WatchCommandContext) async -> WatchCommandResult
    ) async -> WatchCommandResult {
        let key = WatchCommandRequestCache.Key(appUUID: appUUID, requestID: requestID)
        // read before admission, so a revocation while queued is still seen
        let grant = authorization.current

        let ticket: WatchCommandRequestCache.Ticket
        switch await cache.admit(key, command: command, now: now()) {
        case let .accepted(admitted):
            ticket = admitted
        case let .completed(result):
            log.debug("Watch \(name) command repeated, sending the earlier result again")
            return result
        case .inProgress:
            log.debug("Watch \(name) command repeated while the first one is still running")
            return WatchCommandResult(
                acknowledged: false,
                ackCode: .inProgress,
                message: String(localized: "Request is already in progress.", comment: "Watch command ack")
            )
        case .conflict:
            log.warning("Watch \(name) command refused, its request ID was already used for another command")
            return .failure(String(localized: "Request ID was already used.", comment: "Watch command ack"))
        case .full:
            log.warning("Watch \(name) command refused, too many commands are running")
            return .failure(String(localized: "Too many requests in progress. Please try again.", comment: "Watch command ack"))
        }

        let context = WatchCommandContext(
            issuedAt: issuedAt,
            name: name,
            grant: grant,
            authorization: authorization,
            gate: gate,
            now: now,
            log: log
        )
        let result: WatchCommandResult
        if let rejection = context.rejection(checkingExpiry: true) {
            result = rejection
        } else {
            result = await execute(context)
        }
        await cache.complete(ticket, result: result)

        log.info("Watch \(name) command \(result.acknowledged ? "done" : "not done") (\(result.ackCode.rawValue))")
        return result
    }
}

/// Stable, content-free labels for errors: Core Data errors can carry treatment values or store paths.
enum WatchCommandErrorCategory {
    static func name(for error: Error) -> String {
        switch error {
        case is CoreDataError:
            return "coreData"
        case is CancellationError:
            return "cancelled"
        default:
            let nsError = error as NSError
            // the Cocoa code identifies Core Data failures without their user info
            return nsError.domain == NSCocoaErrorDomain ? "cocoa(\(nsError.code))" : "unexpected"
        }
    }
}
