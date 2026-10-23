import Foundation

struct ReportDraft: Codable, Equatable {
    static let maxTitleLength = 200
    static let maxDescriptionLength = 20000
    static let storageKey = "ReportProblem.draft"

    var title = ""
    var description = ""
    var attachLogs = true
    var isAnonymous = true
    var contact = ProblemReport.Contact()

    var trimmedDescription: String {
        description.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var canSubmit: Bool {
        !trimmedDescription.isEmpty && description.count <= Self.maxDescriptionLength
    }

    func report(context: ProblemReport.Context, attachments: [ProblemReport.Attachment]) -> ProblemReport {
        let title = String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxTitleLength))
        return ProblemReport(
            title: title.isEmpty ? nil : title,
            description: String(trimmedDescription.prefix(Self.maxDescriptionLength)),
            contact: isAnonymous ? nil : contact.trimmed,
            context: context,
            attachments: attachments
        )
    }

    static func load(from storage: KeyValueStorage = UserDefaults.standard) -> ReportDraft {
        storage.getValue(ReportDraft.self, forKey: storageKey, defaultValue: nil, reportError: false) ?? ReportDraft()
    }

    func save(to storage: KeyValueStorage = UserDefaults.standard) {
        storage.setValue(self, forKey: Self.storageKey)
    }

    static func clear(in storage: KeyValueStorage = UserDefaults.standard) {
        storage.setValue(ReportDraft?.none, forKey: storageKey)
    }
}
