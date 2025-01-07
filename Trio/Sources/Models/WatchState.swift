import Foundation
import SwiftUI

struct WatchState: Hashable, Equatable, Sendable {
    var currentGlucose: String?
    var trend: String?
    var delta: String?
    var glucoseValues: [(date: Date, glucose: Double, color: Color)] = []
    var units: GlucoseUnits = .mgdL
    var iob: String?
    var cob: String?
    var lastLoopTime: String?
    var overridePresets: [OverridePresetWatch] = []
    var tempTargetPresets: [TempTargetPresetWatch] = []

    // Safety limits
    var maxBolus: Decimal = 10.0
    var maxCarbs: Decimal = 250
    var maxFat: Decimal = 250
    var maxProtein: Decimal = 250
    var maxIOB: Decimal = 0
    var maxCOB: Decimal = 120

    static func == (lhs: WatchState, rhs: WatchState) -> Bool {
        lhs.currentGlucose == rhs.currentGlucose &&
            lhs.trend == rhs.trend &&
            lhs.delta == rhs.delta &&
            lhs.glucoseValues.count == rhs.glucoseValues.count &&
            zip(lhs.glucoseValues, rhs.glucoseValues).allSatisfy {
                $0.0.date == $0.1.date && $0.0.glucose == $0.1.glucose && $0.0.color == $0.1.color
            } &&
            lhs.units == rhs.units &&
            lhs.iob == rhs.iob &&
            lhs.cob == rhs.cob &&
            lhs.lastLoopTime == rhs.lastLoopTime &&
            lhs.overridePresets == rhs.overridePresets &&
            lhs.tempTargetPresets == rhs.tempTargetPresets &&
            lhs.maxBolus == rhs.maxBolus &&
            lhs.maxCarbs == rhs.maxCarbs &&
            lhs.maxFat == rhs.maxFat &&
            lhs.maxProtein == rhs.maxProtein &&
            lhs.maxIOB == rhs.maxIOB &&
            lhs.maxCOB == rhs.maxCOB
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(currentGlucose)
        hasher.combine(trend)
        hasher.combine(delta)
        for value in glucoseValues {
            hasher.combine(value.date)
            hasher.combine(value.glucose)
            hasher.combine(value.color)
        }
        hasher.combine(units)
        hasher.combine(iob)
        hasher.combine(cob)
        hasher.combine(lastLoopTime)
        hasher.combine(overridePresets)
        hasher.combine(tempTargetPresets)
        hasher.combine(maxBolus)
        hasher.combine(maxCarbs)
        hasher.combine(maxFat)
        hasher.combine(maxProtein)
        hasher.combine(maxIOB)
        hasher.combine(maxCOB)
    }
}
