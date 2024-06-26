import AppIntents
import Foundation

@available(iOS 16.0, *) struct ListStateIntent: AppIntent {
    // Title of the action in the Shortcuts app
    static var title = LocalizedStringResource("List last state available", table: "ShortcutsDetail")

    var stateIntent = StateIntentRequest()

    // Description of the action in the Shortcuts app
    static var description = IntentDescription(
        LocalizedStringResource("Allow to list the last Blood Glucose, trends, IOB and COB available", table: "ShortcutsDetail")
    )

    static var parameterSummary: some ParameterSummary {
        Summary("List all states available currently", table: "ShortcutsDetail")
    }

    @MainActor func perform() async throws -> some ReturnsValue<StateResults> & ShowsSnippetView {
        let glucoseValues = try? stateIntent.getLastBG()
        let iob_cob_value = try? stateIntent.getIOB_COB()

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
