import AppIntents
import Foundation

@available(iOS 16.0, *) struct ListStateIntent: AppIntent {
    // Title of the action in the Shortcuts app
    static var title: LocalizedStringResource = "List last state available with Trio"

    // Description of the action in the Shortcuts app
    static var description = IntentDescription(
        "Allow to list the last glucose reading, trends, IOB and COB available in Trio"
    )

    static var parameterSummary: some ParameterSummary {
        Summary("List all states of Trio")
    }

    @MainActor func perform() async throws -> some ReturnsValue<StateResults> & ShowsSnippetView {
        let context = CoreDataStack.shared.persistentContainer.viewContext
        let stateIntent = StateIntentRequest()

        let glucoseValues = try? stateIntent.getLastGlucose(onContext: context)
        let iob_cob_value = try? stateIntent.getIobAndCob(onContext: context)

        guard let glucoseValue = glucoseValues else { throw StateIntentError.NoBG }
        guard let iob_cob = iob_cob_value else { throw StateIntentError.NoIOBCOB }
        let BG = StateResults(
            glucose: glucoseValue.glucose,
            trend: glucoseValue.trend,
            delta: glucoseValue.delta,
            date: glucoseValue.dateGlucose,
            iob: iob_cob.iob,
            cob: iob_cob.cob,
            unit: stateIntent.settingsManager.settings.units
        )
        return .result(
            value: BG,
            view: ListStateView(state: BG)
        )
    }
}
