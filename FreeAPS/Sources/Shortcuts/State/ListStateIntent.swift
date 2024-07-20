import AppIntents
import Foundation

@available(iOS 16.0, *) struct ListStateIntent: AppIntent {
    // Title of the action in the Shortcuts app
    static var title: LocalizedStringResource = "List last state available with Trio"

    var stateIntent = StateIntentRequest()

    // Description of the action in the Shortcuts app
    static var description = IntentDescription(
        "Allow to list the last Blood Glucose, trends, IOB and COB available in Trio"
    )

    static var parameterSummary: some ParameterSummary {
        Summary("List all states of Trio")
    }

<<<<<<< HEAD
    @MainActor func perform() async throws -> some ReturnsValue<StateiAPSResults> & ShowsSnippetView {
        let context = CoreDataStack.shared.persistentContainer.viewContext

        let glucoseValues = try? stateIntent.getLastGlucose(onContext: context)
        let iob_cob_value = try? stateIntent.getIobAndCob(onContext: context)
=======
    @MainActor func perform() async throws -> some ReturnsValue<StateResults> & ShowsSnippetView {
        let glucoseValues = try? stateIntent.getLastBG()
        let iob_cob_value = try? stateIntent.getIOB_COB()
>>>>>>> 9672da256c317a314acc76d6e4f6e82cc174d133

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
        let iob_text = String(format: "%.2f", iob_cob.iob)
        let cob_text = String(format: "%.2f", iob_cob.cob)
        return .result(
            value: BG,
            view: ListStateView(state: BG)
        )
    }
}
