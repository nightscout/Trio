import Foundation

struct SentReport: Codable, Equatable, Identifiable {
    let id: String
    let date: Date
}

enum SentReports {
    static let storageKey = "ReportProblem.sentReports"
    static let retention: TimeInterval = 90 * 24 * 60 * 60

    // Newest first; the server deletes reports after 90 days, so older entries are dropped
    static func load(from storage: KeyValueStorage = UserDefaults.standard, now: Date = Date()) -> [SentReport] {
        let reports = storage.getValue([SentReport].self, forKey: storageKey, defaultValue: nil, reportError: false) ?? []
        return reports.filter { now.timeIntervalSince($0.date) < retention }.sorted { $0.date > $1.date }
    }

    static func add(_ id: String, date: Date = Date(), in storage: KeyValueStorage = UserDefaults.standard) {
        let reports = load(from: storage, now: date).filter { $0.id != id }
        storage.setValue([SentReport(id: id, date: date)] + reports, forKey: storageKey)
    }

    static func remove(_ id: String, in storage: KeyValueStorage = UserDefaults.standard) {
        storage.setValue(load(from: storage).filter { $0.id != id }, forKey: storageKey)
    }
}
