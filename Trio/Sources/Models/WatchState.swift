import Foundation

// TODO: expand this for cob,iob etc
struct WatchState: Hashable, Equatable, Sendable {
    var currentGlucose: String?
    var trend: String?
    var delta: String?
    var glucoseValues: [(date: Date, glucose: Double)] = []
    var units: GlucoseUnits = .mmolL

    static func == (lhs: WatchState, rhs: WatchState) -> Bool {
        lhs.currentGlucose == rhs.currentGlucose &&
            lhs.trend == rhs.trend &&
            lhs.delta == rhs.delta &&
            lhs.glucoseValues.count == rhs.glucoseValues.count &&
            zip(lhs.glucoseValues, rhs.glucoseValues).allSatisfy {
                $0.0.date == $0.1.date && $0.0.glucose == $0.1.glucose
            } &&
            lhs.units == rhs.units
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(currentGlucose)
        hasher.combine(trend)
        hasher.combine(delta)
        // Hash each element individually
        for value in glucoseValues {
            hasher.combine(value.date)
            hasher.combine(value.glucose)
        }
        hasher.combine(units)
    }
}
