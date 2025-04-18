import Foundation
import SwiftUI

struct WatchState: Hashable, Equatable, Sendable, Encodable, Decodable {
    var date: Date
    var currentGlucose: String?
    var currentGlucoseColorString: String?
    var trend: String?
    var delta: String?
    var glucoseValues: [WatchGlucoseObject] = []
    var minYAxisValue: Decimal = 39.0
    var maxYAxisValue: Decimal = 200.0
    var units: GlucoseUnits = .mgdL
    var iob: String?
    var cob: String?
    var lastLoopTime: String?
    var overridePresets: [OverridePresetWatch] = []
    var tempTargetPresets: [TempTargetPresetWatch] = []

    // Safety limits
    var maxBolus: Decimal = 10.0
    var maxCarbs: Decimal = 250.0
    var maxFat: Decimal = 250.0
    var maxProtein: Decimal = 250.0

    // Pump specific dosing increment
    var bolusIncrement: Decimal = 0.05
    var confirmBolusFaster: Bool = false

    static func == (lhs: WatchState, rhs: WatchState) -> Bool {
        lhs.date == rhs.date &&
            lhs.currentGlucose == rhs.currentGlucose &&
            lhs.trend == rhs.trend &&
            lhs.delta == rhs.delta &&
            lhs.glucoseValues.count == rhs.glucoseValues.count &&
            zip(lhs.glucoseValues, rhs.glucoseValues).allSatisfy {
                $0.0.date == $0.1.date && $0.0.glucose == $0.1.glucose && $0.0.color == $0.1.color
            } &&
            lhs.minYAxisValue == rhs.minYAxisValue &&
            lhs.maxYAxisValue == rhs.maxYAxisValue &&
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
            lhs.bolusIncrement == rhs.bolusIncrement &&
            lhs.confirmBolusFaster == rhs.confirmBolusFaster
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(date)
        hasher.combine(currentGlucose)
        hasher.combine(trend)
        hasher.combine(delta)
        for value in glucoseValues {
            hasher.combine(value.date)
            hasher.combine(value.glucose)
            hasher.combine(value.color)
        }
        hasher.combine(minYAxisValue)
        hasher.combine(maxYAxisValue)
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
        hasher.combine(bolusIncrement)
        hasher.combine(confirmBolusFaster)
    }
}

//
///// Codable snapshot used for saving/loading WatchState to disk
// struct WatchStateSnapshot: Codable {
//    let state: WatchState
//    let timestamp: TimeInterval
//
//    init(state: WatchState) {
//        self.state = state
//        self.timestamp = state.date.timeIntervalSince1970
//    }
// }
//
// extension WatchState {
//    // MARK: - Disk Persistence
//
//    private static var snapshotURL: URL {
//        let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.trio.watch") ?? FileManager.default.temporaryDirectory
//        return dir.appendingPathComponent("watch_state_snapshot.json")
//    }
//
//    static func loadFromDisk() -> WatchState? {
//        let url = snapshotURL
//        guard FileManager.default.fileExists(atPath: url.path) else {
//            return nil
//        }
//
//        do {
//            let data = try Data(contentsOf: url)
//            let snapshot = try JSONDecoder().decode(WatchStateSnapshot.self, from: data)
//            return snapshot.state
//        } catch {
//            print("⌚️ Failed to load WatchState snapshot: \(error.localizedDescription)")
//            return nil
//        }
//    }
//
//    static func loadLatestDateFromDisk() -> Date {
//        let url = snapshotURL
//        guard FileManager.default.fileExists(atPath: url.path) else {
//            return Date(timeIntervalSince1970: 0)
//        }
//
//        do {
//            let data = try Data(contentsOf: url)
//            let snapshot = try JSONDecoder().decode(WatchStateSnapshot.self, from: data)
//            return Date(timeIntervalSince1970: snapshot.timestamp)
//        } catch {
//            print("⌚️ Failed to load timestamp from WatchState snapshot: \(error.localizedDescription)")
//            return Date(timeIntervalSince1970: 0)
//        }
//    }
//
//
//    func saveToDisk() {
//        let snapshot = WatchStateSnapshot(state: self)
//        let url = Self.snapshotURL
//
//        do {
//            let data = try JSONEncoder().encode(snapshot)
//            try data.write(to: url, options: .atomic)
//        } catch {
//            print("⌚️ Failed to save WatchState snapshot: \(error.localizedDescription)")
//        }
//    }
// }
