import AppIntents

struct TrioWatchApp: AppIntent {
    static var title: LocalizedStringResource { "Trio Watch App" }

    func perform() async throws -> some IntentResult {
        .result()
    }
}
