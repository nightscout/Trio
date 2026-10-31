import Foundation

struct ReportDraft: Codable, Equatable {
    static let maxTitleLength = 200
    static let maxDescriptionLength = 20000
    static let maxContactLength = 200
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
        !trimmedDescription.isEmpty && description.unicodeScalars.count <= Self.maxDescriptionLength
    }

    func report(context: ProblemReport.Context, attachments: [ProblemReport.Attachment]) -> ProblemReport {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(scalars: Self.maxTitleLength)
        return ProblemReport(
            title: title.isEmpty ? nil : title,
            description: trimmedDescription.prefix(scalars: Self.maxDescriptionLength),
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

extension String {
    // The server counts Unicode code points, not characters
    func prefix(scalars limit: Int) -> String {
        String(String.UnicodeScalarView(unicodeScalars.prefix(limit)))
    }
}
