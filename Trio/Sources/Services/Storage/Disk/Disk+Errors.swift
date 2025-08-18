import Foundation

public extension Disk {
    enum ErrorCode: Int {
        case noFileFound = 0
        case serialization = 1
        case deserialization = 2
        case invalidFileName = 3
        case couldNotAccessTemporaryDirectory = 4
        case couldNotAccessUserDomainMask = 5
        case couldNotAccessSharedContainer = 6
    }

    static let errorDomain = "DiskErrorDomain"

    /// Create custom error that FileManager can't account for
    internal static func createError(
        _ errorCode: ErrorCode,
        description: String?,
        failureReason: String?,
        recoverySuggestion: String?
    ) -> Error {
        let errorInfo: [String: Any] = [
            NSLocalizedDescriptionKey: description ?? "",
            NSLocalizedRecoverySuggestionErrorKey: recoverySuggestion ?? "",
            NSLocalizedFailureReasonErrorKey: failureReason ?? ""
        ]
        return NSError(domain: errorDomain, code: errorCode.rawValue, userInfo: errorInfo) as Error
    }
}
