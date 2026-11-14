import Foundation
import os
import SwiftUI

struct ComplicationPoint: Codable, Equatable {
    var timestamp: TimeInterval
    var glucose: Double

    private enum CodingKeys: String, CodingKey {
        case timestamp = "t"
        case glucose = "v"
    }
}

struct ComplicationSlotSettings {
    var cornerValue = WatchComplicationDefaults.cornerValue
    var secondaryValue = WatchComplicationDefaults.secondaryValue
    var staleMinutes = WatchComplicationDefaults.staleMinutes
}

struct ComplicationState: Codable, Equatable {
    var date: Date
    var glucose: String
    var glucoseColorHex: String
    var trend: String
    var delta: String
    var iob: String
    var cob: String
    var lastLoopTime: String

    var cornerValue: WatchComplicationValue
    var secondaryValue: WatchComplicationValue
    var staleMinutes: Int

    var units: String
    var glucoseValue: Double?
    var history: [ComplicationPoint]
    var loopDate: Date?
    var limits: ClosedRange<Double>?
    var ringStops: [ComplicationRingStop]?

    static let missingValue = "--"
    static let defaultUnits = "mg/dL"

    private static let sampleReadingSpacing: TimeInterval = 5 * 60
    private static let maxLoopAgeMinutes = 1440
    private static let sampleMmolCurve: [Double] = [
        8.9, 8.6, 8.3, 8.0, 7.7, 7.4, 7.1, 6.9, 6.7, 6.5, 6.3, 6.1,
        6.0, 5.9, 5.8, 5.8, 5.7, 5.7, 5.8, 5.9, 6.1, 6.3, 6.6, 6.9,
        7.1, 7.2, 7.2, 7.1, 7.0, 6.9, 6.8, 6.7, 6.6, 6.5, 6.4, 6.4
    ]

    static let placeholder = ComplicationState(
        date: .distantPast,
        glucose: missingValue,
        glucoseColorHex: "#ffffff",
        trend: "",
        delta: missingValue,
        iob: missingValue,
        cob: missingValue,
        lastLoopTime: missingValue,
        cornerValue: WatchComplicationDefaults.cornerValue,
        secondaryValue: WatchComplicationDefaults.secondaryValue,
        staleMinutes: WatchComplicationDefaults.staleMinutes,
        units: defaultUnits,
        glucoseValue: nil,
        history: [],
        loopDate: nil,
        limits: nil,
        ringStops: nil
    )

    static func sample(
        units: String,
        settings: ComplicationSlotSettings = ComplicationSlotSettings(),
        ringStops: [ComplicationRingStop]? = nil,
        date: Date = Date()
    ) -> ComplicationState {
        let mmol = Self.isMmol(units)
        let history = sampleHistory(isMmol: mmol, endingAt: date)
        return ComplicationState(
            date: date,
            glucose: mmol ? "6.4" : "115",
            glucoseColorHex: "#4cd964",
            trend: "Flat",
            delta: mmol ? "+0.0" : "0",
            iob: "1.25",
            cob: "12",
            lastLoopTime: "2 min",
            cornerValue: settings.cornerValue,
            secondaryValue: settings.secondaryValue,
            staleMinutes: settings.staleMinutes,
            units: units,
            glucoseValue: history.last?.glucose,
            history: history,
            loopDate: date.addingTimeInterval(-2 * 60),
            limits: typicalBand(isMmol: mmol),
            ringStops: ringStops
        )
    }

    private static func sampleHistory(isMmol: Bool, endingAt date: Date) -> [ComplicationPoint] {
        let curve = isMmol ? sampleMmolCurve : sampleMmolCurve.map { ($0 * WatchComplicationDefaults.mgdlPerMmol).rounded() }
        let start = date.timeIntervalSince1970 - TimeInterval(curve.count - 1) * sampleReadingSpacing
        return curve.enumerated().map { index, glucose in
            ComplicationPoint(timestamp: start + TimeInterval(index) * sampleReadingSpacing, glucose: glucose)
        }
    }

    private static func typicalBand(isMmol: Bool) -> ClosedRange<Double> {
        isMmol ? 3.9 ... 10.0 : 70 ... 180
    }

    static let chartWindow: TimeInterval = 3 * 60 * 60

    static func isMmol(_ units: String) -> Bool {
        units.lowercased().hasPrefix("mmol")
    }

    var isMmol: Bool { Self.isMmol(units) }

    var staleAfter: TimeInterval { TimeInterval(staleMinutes) * 60 }

    var gaugeRange: ClosedRange<Double> {
        isMmol ? WatchComplicationDefaults.gaugeRangeMmol : WatchComplicationDefaults.gaugeRangeMgdl
    }

    var inRangeBand: ClosedRange<Double> {
        limits ?? Self.typicalBand(isMmol: isMmol)
    }

    var chartMinimumSpan: Double {
        isMmol ? 1 : 18
    }

    var gaugeValue: Double? {
        guard let value = glucoseValue, value.isFinite else { return nil }
        return min(max(value, gaugeRange.lowerBound), gaugeRange.upperBound)
    }

    var trendArrow: String {
        switch trend {
        case "TripleUp": return "↑↑↑"
        case "DoubleUp": return "↑↑"
        case "SingleUp": return "↑"
        case "FortyFiveUp": return "↗︎"
        case "Flat": return "→"
        case "FortyFiveDown": return "↘︎"
        case "SingleDown": return "↓"
        case "DoubleDown": return "↓↓"
        case "TripleDown": return "↓↓↓"
        default: return ""
        }
    }

    static func presentOrMissing(_ value: String?) -> String {
        guard let value = value, !value.isEmpty else { return missingValue }
        return value
    }

    func isStale(at reference: Date) -> Bool {
        reference.timeIntervalSince(date) > staleAfter
    }

    func isLoopStale(at reference: Date) -> Bool {
        guard let loopDate = loopDate else { return false }
        return reference.timeIntervalSince(loopDate) > staleAfter
    }

    func staleTransitionDates(after now: Date, within span: TimeInterval) -> [Date] {
        let end = now.addingTimeInterval(span)
        return [date, loopDate]
            .compactMap { $0?.addingTimeInterval(staleAfter + 1) }
            .filter { $0 > now && $0 < end }
    }

    func loopAgeText(at reference: Date) -> String {
        guard let loopDate = loopDate else { return lastLoopTime }
        let minutes = max(0, Int(reference.timeIntervalSince(loopDate) / 60))
        return minutes > Self.maxLoopAgeMinutes ? Self.missingValue : "\(minutes) min"
    }

    func minutesAgo(at reference: Date) -> Int {
        max(0, Int(reference.timeIntervalSince(date) / 60))
    }

    func labelledText(for value: WatchComplicationValue, withArrow: Bool = true) -> String {
        switch value {
        case .nothing: return ""
        case .iob: return "IOB \(iob)"
        case .cob: return "COB \(cob)"
        case .delta: return deltaText(withArrow: withArrow)
        case .loopAge: return "Loop \(lastLoopTime)"
        }
    }

    func plainText(for value: WatchComplicationValue, withArrow: Bool = true) -> String {
        switch value {
        case .nothing: return ""
        case .iob: return iob
        case .cob: return cob
        case .delta: return deltaText(withArrow: withArrow)
        case .loopAge: return lastLoopTime
        }
    }

    private func deltaText(withArrow: Bool) -> String {
        guard withArrow else { return delta }
        return "\(trendArrow) \(delta)".trimmingCharacters(in: .whitespaces)
    }

    var glucoseColor: Color {
        Color(complicationHex: glucoseColorHex) ?? .white
    }
}

final class ComplicationReloader {
    typealias InstalledKindsFetch = (@escaping ([String]) -> Void) -> Void

    private(set) var isReloading = false
    private let fetchInstalledKinds: InstalledKindsFetch
    private let reloadTimelines: (String) -> Void

    init(fetchInstalledKinds: @escaping InstalledKindsFetch, reloadTimelines: @escaping (String) -> Void) {
        self.fetchInstalledKinds = fetchInstalledKinds
        self.reloadTimelines = reloadTimelines
    }

    func reload(_ kinds: Set<String>) {
        isReloading = true
        fetchInstalledKinds { [self] installedKinds in
            Set(installedKinds).intersection(kinds).forEach(reloadTimelines)
            isReloading = false
        }
    }
}

enum ComplicationStoreError: Error {
    case noAppGroup
}

enum ComplicationStore {
    static let key = "ComplicationState.latest"

    private static let logger = os.Logger(subsystem: "org.nightscout.trio", category: "ComplicationStore")

    static var appGroupID: String? {
        appGroupID(from: Bundle.main.object(forInfoDictionaryKey: "AppGroupID"))
    }

    static func appGroupID(from plistValue: Any?) -> String? {
        guard let fromPlist = plistValue as? String,
              !fromPlist.isEmpty, !fromPlist.hasPrefix("$(")
        else {
            logger.error("AppGroupID missing from Info.plist")
            return nil
        }
        return fromPlist
    }

    static let defaults: UserDefaults? = appGroupID.flatMap { UserDefaults(suiteName: $0) }

    static func save(_ state: ComplicationState) throws {
        guard let defaults = defaults else { throw ComplicationStoreError.noAppGroup }
        defaults.set(try JSONEncoder().encode(state), forKey: key)
    }

    static func load() -> ComplicationState? {
        guard let data = defaults?.data(forKey: key) else { return nil }
        do {
            return try JSONDecoder().decode(ComplicationState.self, from: data)
        } catch {
            logger.error("Complication snapshot unreadable: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}

extension Color {
    init?(complicationHex hex: String) {
        var digits = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if digits.hasPrefix("#") { digits.removeFirst() }
        guard digits.count == 6, let value = UInt64(digits, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
