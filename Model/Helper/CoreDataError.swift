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
            return String(localized: "Failed to create a new object in \(function) from \(file).")
        case let .batchInsertError(function, file):
            return String(localized: "Failed to execute a batch insert request in \(function) from \(file).")
        case let .batchDeleteError(function, file):
            return String(localized: "Failed to execute a batch delete request in \(function) from \(file).")
        case let .persistentHistoryChangeError(function, file):
            return String(localized: "Failed to execute a persistent history change request in \(function) from \(file).")
        case let .unexpectedError(error, function, file):
            return String(localized: "Received unexpected error in \(function) from \(file): \(error.localizedDescription)")
        case let .fetchError(function, file):
            return String(localized: "Failed to fetch object \(DebuggingIdentifiers.failed) in \(function) from \(file).")
        case let .validationError(function, file):
            return String(localized: "Failed to validate object in \(function) from \(file).")
        case let .storeNotInitializedError(function, file):
            return String(localized: "Store not initialized in \(function) from \(file).")
        }
    }
}

extension CoreDataError: Identifiable {
    var id: String? {
        errorDescription
    }
}
