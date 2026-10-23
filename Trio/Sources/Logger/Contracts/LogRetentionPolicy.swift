import Foundation

struct LogRetentionPolicy: Equatable {
    var maxAge: TimeInterval
    var persistsDebug: Bool
    var maxRows: Int

    static let `default` = LogRetentionPolicy(
        maxAge: 8 * 24 * 60 * 60,
        persistsDebug: true,
        maxRows: 250_000
    )
}
