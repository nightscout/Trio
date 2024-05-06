import AppIntents
import Foundation

enum StateIntentError: Error {
    case StateIntentUnknownError
    case NoBG
    case NoIOBCOB
}

@available(iOS 16, *) struct StateiAPSResults: AppEntity {
    static var defaultQuery = StateBGQuery()

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Trio State Result"

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(glucose)")
    }

    var id: UUID
    @Property(title: "Glucose") var glucose: String

    @Property(title: "Trend") var trend: String

    @Property(title: "Delta") var delta: String

    @Property(title: "Date") var date: Date

    @Property(title: "IOB") var iob: Double?

    @Property(title: "COB") var cob: Double?

    @Property(title: "unit") var unit: String?

    init(glucose: String, trend: String, delta: String, date: Date, iob: Double, cob: Double, unit: GlucoseUnits) {
        id = UUID()
        self.glucose = glucose
        self.trend = trend
        self.delta = delta
        self.date = date
        self.iob = iob
        self.cob = cob
        self.unit = unit.rawValue
    }
}

@available(iOS 16.0, *) struct StateBGQuery: EntityQuery {
    func entities(for _: [StateiAPSResults.ID]) async throws -> [StateiAPSResults] {
        []
    }

    func suggestedEntities() async throws -> [StateiAPSResults] {
        []
    }
}

@available(iOS 16.0, *) final class StateIntentRequest: BaseIntentsRequest {
    @Injected() private var glucoseStorage: GlucoseStorage!
    @Injected() private var carbsStorage: CarbsStorage!
    @Injected() private var apsManager: APSManager!

    func getLastBG() throws -> (dateGlucose: Date, glucose: String, trend: String, delta: String) {
        let glucose = glucoseStorage.recent()
        guard let lastGlucose = glucose.last, let glucoseValue = lastGlucose.glucose else { throw StateIntentError.NoBG }
        let delta = glucose.count >= 2 ? glucoseValue - (glucose[glucose.count - 2].glucose ?? 0) : nil
        let units = settingsManager.settings.units

        let glucoseText = glucoseFormatter
            .string(from: Double(
                units == .mmolL ? glucoseValue
                    .asMmolL : Decimal(glucoseValue)
            ) as NSNumber)!
        let directionText = lastGlucose.direction?.rawValue ?? "none"
        let deltaText = delta
            .map {
                self.deltaFormatter
                    .string(from: Double(
                        units == .mmolL ? $0
                            .asMmolL : Decimal($0)
                    ) as NSNumber)!
            } ?? "--"

        return (lastGlucose.dateString, glucoseText, directionText, deltaText)
    }

    func getIOB_COB() throws -> (iob: Double, cob: Double) {
        let iob = suggestion?.iob ?? 0.0
        let cob = suggestion?.cob ?? 0.0
        let iob_double = Double(truncating: iob as NSNumber)
        let cob_double = Double(truncating: cob as NSNumber)
        return (iob_double, cob_double)
    }

    private var suggestion: Suggestion? {
        fileStorage.retrieve(OpenAPS.Enact.suggested, as: Suggestion.self)
    }

    private var glucoseFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        if settingsManager.settings.units == .mmolL {
            formatter.minimumFractionDigits = 1
            formatter.maximumFractionDigits = 1
        }
        formatter.roundingMode = .halfUp
        return formatter
    }

    private var deltaFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        formatter.positivePrefix = "+"
        return formatter
    }
}
