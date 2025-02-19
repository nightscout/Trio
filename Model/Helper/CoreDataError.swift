import Foundation

enum CoreDataError: Error {
    case creationError
    case batchInsertError
    case batchDeleteError
    case persistentHistoryChangeError
    case unexpectedError(error: Error)
    case fetchError
}

extension CoreDataError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .creationError:
            return String(localized: "Failed to create a new object.", comment: "")
        case .batchInsertError:
            return String(localized: "Failed to execute a batch insert request.", comment: "")
        case .batchDeleteError:
            return String(localized: "Failed to execute a batch delete request.", comment: "")
        case .persistentHistoryChangeError:
            return String(localized: "Failed to execute a persistent history change request.", comment: "")
        case let .unexpectedError(error):
            return String(localized: "Received unexpected error. \(error.localizedDescription)", comment: "")
        case .fetchError:
            return String(localized: "Failed to fetch object \(DebuggingIdentifiers.failed).", comment: "")
        }
    }
}

extension CoreDataError: Identifiable {
    var id: String? {
        errorDescription
    }
}
