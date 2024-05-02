import AppIntents
import Foundation

@available(iOS 16.0, *) struct ListStateIntent: AppIntent {
    // Title of the action in the Shortcuts app
    static var title: LocalizedStringResource = "List last state available with iAPS"

    var stateIntent = StateIntentRequest()

    // Description of the action in the Shortcuts app
    static var description = IntentDescription(
        "Allow to list the last Blood Glucose, trends, IOB and COB available in iAPS"
    )

    static var parameterSummary: some ParameterSummary {
        Summary("List all states of Open-iAPS")
    }

    @MainActor func perform() async throws -> some ReturnsValue<StateiAPSResults> & ShowsSnippetView {
        let glucoseValues = try? stateIntent.getLastBG()
        let iob_cob_value = try? stateIntent.getIOB_COB()

        guard let glucoseValue = glucoseValues else { throw StateIntentError.NoBG }
        guard let iob_cob = iob_cob_value else { throw StateIntentError.NoIOBCOB }
        let BG = StateiAPSResults(
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
