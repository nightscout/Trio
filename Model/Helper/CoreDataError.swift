import Foundation

enum CoreDataError: Error {
    case validationError(function: String, file: String)
    case creationError(function: String, file: String)
    case batchInsertError(function: String, file: String)
    case batchDeleteError(function: String, file: String)
    case persistentHistoryChangeError(function: String, file: String)
    case unexpectedError(error: Error, function: String, file: String)
    case fetchError(function: String, file: String)
    case storeNotInitializedError(function: String, file: String)
}

extension CoreDataError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case let .creationError(function, file):
            return NSLocalizedString("Failed to create a new object in \(function) from \(file).", comment: "")
        case let .batchInsertError(function, file):
            return NSLocalizedString("Failed to execute a batch insert request in \(function) from \(file).", comment: "")
        case let .batchDeleteError(function, file):
            return NSLocalizedString("Failed to execute a batch delete request in \(function) from \(file).", comment: "")
        case let .persistentHistoryChangeError(function, file):
            return NSLocalizedString(
                "Failed to execute a persistent history change request in \(function) from \(file).",
                comment: ""
            )
        case let .unexpectedError(error, function, file):
            return NSLocalizedString(
                "Received unexpected error in \(function) from \(file): \(error.localizedDescription)",
                comment: ""
            )
        case let .fetchError(function, file):
            return NSLocalizedString(
                "Failed to fetch object \(DebuggingIdentifiers.failed) in \(function) from \(file).",
                comment: ""
            )
        case let .validationError(function, file):
            return NSLocalizedString("Failed to validate object in \(function) from \(file).", comment: "")
        case let .storeNotInitializedError(function, file):
            return NSLocalizedString(
                "Store not initialized in \(function) from \(file).",
                comment: ""
            )
        }
    }
}

extension CoreDataError: Identifiable {
    var id: String? {
        errorDescription
    }
}
