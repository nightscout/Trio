import AppIntents

struct Trio_Watch_App: AppIntent {
    static var title: LocalizedStringResource { "Trio Watch App" }

    func perform() async throws -> some IntentResult {
        .result()
    }
}
