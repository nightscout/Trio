import Foundation
import SwiftUI

/// https://doi.org/10.1177/19322968221085273
enum GRICalculator {
    struct Result: Equatable {
        let veryLowPercentage: Double
        let lowPercentage: Double
        let highPercentage: Double
        let veryHighPercentage: Double

        var hypoComponent: Double { veryLowPercentage + 0.8 * lowPercentage }
        var hyperComponent: Double { veryHighPercentage + 0.5 * highPercentage }
        var score: Double { min(100, uncappedScore) }

        var weightedHypoComponent: Double { 3 * hypoComponent }
        var weightedHyperComponent: Double { 1.6 * hyperComponent }
        var uncappedScore: Double { weightedHypoComponent + weightedHyperComponent }

        var zone: String {
            switch score {
            case ...20: return "A"
            case ...40: return "B"
            case ...60: return "C"
            case ...80: return "D"
            default: return "E"
            }
        }
    }

    static func calculate(glucoseValues: [Int]) -> Result? {
        var count = 0
        var veryLow = 0
        var low = 0
        var high = 0
        var veryHigh = 0
        for value in glucoseValues where value > 0 {
            count += 1
            switch GlucoseBand.classify(value) {
            case .veryLow: veryLow += 1
            case .low: low += 1
            case .tight,
                 .upperMid: break
            case .high: high += 1
            case .veryHigh: veryHigh += 1
            }
        }
        guard count > 0 else { return nil }
        let percent = 100.0 / Double(count)
        return Result(
            veryLowPercentage: Double(veryLow) * percent,
            lowPercentage: Double(low) * percent,
            highPercentage: Double(high) * percent,
            veryHighPercentage: Double(veryHigh) * percent
        )
    }
}

enum GlucoseBand: CaseIterable, Sendable {
    case veryLow
    case low
    case tight
    case upperMid
    case high
    case veryHigh

    static let veryLowThreshold = 54
    static let inRangeThreshold = 180
    static let highThreshold = 250

    static func classify(_ value: Int, timeInRangeType: TimeInRangeType = .timeInTightRange) -> GlucoseBand {
        if value < veryLowThreshold { return .veryLow }
        if value < timeInRangeType.bottomThreshold { return .low }
        if value <= timeInRangeType.topThreshold { return .tight }
        if value <= inRangeThreshold { return .upperMid }
        if value <= highThreshold { return .high }

        return .veryHigh
    }

    var color: Color {
        switch self {
        case .veryLow: .dynamicRed
        case .low: .dynamicOrange
        case .tight: .dynamicGreen
        case .upperMid: .dynamicTeal
        case .high: .dynamicBlue
        case .veryHigh: .dynamicPurple
        }
    }

    func rangeLabel(units: GlucoseUnits, timeInRangeType: TimeInRangeType = .timeInTightRange) -> String {
        let bottom = timeInRangeType.bottomThreshold
        let top = timeInRangeType.topThreshold
        switch self {
        case .veryLow:
            return "<\(Self.formatBound(Self.veryLowThreshold, units: units))"
        case .low:
            return "\(Self.formatBound(Self.veryLowThreshold, units: units))-\(Self.formatBound(bottom, stepOffset: -1, units: units))"
        case .tight:
            return "\(Self.formatBound(bottom, units: units))-\(Self.formatBound(top, units: units))"
        case .upperMid:
            return "\(Self.formatBound(top, stepOffset: 1, units: units))-\(Self.formatBound(Self.inRangeThreshold, units: units))"
        case .high:
            return "\(Self.formatBound(Self.inRangeThreshold, stepOffset: 1, units: units))-\(Self.formatBound(Self.highThreshold, units: units))"
        case .veryHigh:
            return ">\(Self.formatBound(Self.highThreshold, units: units))"
        }
    }

    private static func formatBound(_ mgdL: Int, stepOffset: Int = 0, units: GlucoseUnits) -> String {
        let step: Decimal = units == .mgdL ? 1 : 0.1
        let value = Decimal(mgdL).asUnit(units) + Decimal(stepOffset) * step
        return value.formatted(.number.precision(.fractionLength(units == .mgdL ? 0 : 1)))
    }
}

// Sendable snapshot; Core Data objects cannot cross threads.
struct GlucoseReading: Equatable, Sendable {
    let value: Int
    let date: Date
}

struct GlucoseDailyDistributionStats: Identifiable {
    var id: Date { date }
    let date: Date
    let veryLowPct: Double
    let lowPct: Double
    let inSmallRangePct: Double
    let upperMidPct: Double
    var inRangePct: Double { inSmallRangePct + upperMidPct }
    let highPct: Double
    let veryHighPct: Double

    init(
        date: Date,
        veryLowPct: Double = 0,
        lowPct: Double = 0,
        inSmallRangePct: Double = 0,
        upperMidPct: Double = 0,
        highPct: Double = 0,
        veryHighPct: Double = 0
    ) {
        self.date = date
        self.veryLowPct = veryLowPct
        self.lowPct = lowPct
        self.inSmallRangePct = inSmallRangePct
        self.upperMidPct = upperMidPct
        self.highPct = highPct
        self.veryHighPct = veryHighPct
    }
}

extension GlucoseDailyDistributionStats {
    func pct(for band: GlucoseBand) -> Double {
        switch band {
        case .veryLow: veryLowPct
        case .low: lowPct
        case .tight: inSmallRangePct
        case .upperMid: upperMidPct
        case .high: highPct
        case .veryHigh: veryHighPct
        }
    }

    // Readings must be in mg/dL; band edges are mg/dL constants.
    static func compute(
        date: Date,
        readings: [GlucoseReading],
        timeInRangeType: TimeInRangeType
    ) -> GlucoseDailyDistributionStats {
        let totalReadings = Double(readings.count)

        let grouped = Dictionary(grouping: readings) { reading in
            GlucoseBand.classify(reading.value, timeInRangeType: timeInRangeType)
        }

        let shareOf: (GlucoseBand) -> Double = { band in
            totalReadings > 0 ? Double(grouped[band]?.count ?? 0) / totalReadings * 100 : 0
        }

        return GlucoseDailyDistributionStats(
            date: date,
            veryLowPct: shareOf(.veryLow),
            lowPct: shareOf(.low),
            inSmallRangePct: shareOf(.tight),
            upperMidPct: shareOf(.upperMid),
            highPct: shareOf(.high),
            veryHighPct: shareOf(.veryHigh)
        )
    }
}

struct GlucoseDailyPercentileStats: Identifiable {
    var id: Date { date }
    let date: Date
    let minimum: Double
    let percentile10: Double
    let percentile25: Double
    let median: Double
    let percentile75: Double
    let percentile90: Double
    let maximum: Double

    init(
        date: Date,
        minimum: Double = 0,
        percentile10: Double = 0,
        percentile25: Double = 0,
        median: Double = 0,
        percentile75: Double = 0,
        percentile90: Double = 0,
        maximum: Double = 0
    ) {
        self.date = date
        self.minimum = minimum
        self.percentile10 = percentile10
        self.percentile25 = percentile25
        self.median = median
        self.percentile75 = percentile75
        self.percentile90 = percentile90
        self.maximum = maximum
    }
}

extension Stat.StateModel {
    func setupGlucoseArray(for interval: StatsTimeIntervalWithToday) {
        Task {
            let readings = await fetchGlucose(for: interval)
            // Drop stale results if the picker moved while fetching.
            guard interval == self.selectedIntervalForGlucoseStats else { return }
            let hourly = Self.makeHourlyStats(from: readings)
            let ranges = Self.makeGlucoseRangeStats(
                from: readings,
                timeInRangeType: timeInRangeType
            )
            let gri = GRICalculator.calculate(glucoseValues: readings.map(\.value))

            await MainActor.run {
                self.glucoseFromPersistence = readings
                self.hourlyStats = hourly
                self.glucoseRangeStats = ranges
                self.griResult = gri
            }
        }
    }

    func setupGlucoseDailyStats() {
        Task {
            let readings = await fetchGlucose(for: .total)

            let grouped = Dictionary(grouping: readings) { Calendar.current.startOfDay(for: $0.date) }
            let groupSorted = grouped.sorted { $0.key < $1.key }

            let percentile = groupSorted.map { group in
                Self.dailyPercentileStats(date: group.key, readings: group.value)
            }
            let distribution = groupSorted.map { group in
                GlucoseDailyDistributionStats.compute(
                    date: group.key, readings: group.value, timeInRangeType: timeInRangeType
                )
            }
            await MainActor.run {
                self.glucoseReadingsByDay = grouped
                self.dailyGlucosePercentileStats = percentile
                self.dailyGlucoseDistributionStats = distribution
            }
        }
    }

    private func fetchGlucose(for interval: StatsTimeIntervalWithToday) async -> [GlucoseReading] {
        do {
            let glucoseTaskContext = CoreDataStack.shared.newTaskContext()
            glucoseTaskContext.name = "StatStateModel.fetchGlucose"

            let predicate: NSPredicate
            switch interval {
            case .day: predicate = NSPredicate.glucoseForStatsDay
            case .week: predicate = NSPredicate.glucoseForStatsWeek
            case .today: predicate = NSPredicate.glucoseForStatsToday
            case .month: predicate = NSPredicate.glucoseForStatsMonth
            case .total: predicate = NSPredicate.glucoseForStatsTotal
            }

            let results = try await CoreDataStack.shared.fetchEntitiesAsync(
                ofType: GlucoseStored.self,
                onContext: glucoseTaskContext,
                predicate: predicate,
                key: "date",
                ascending: false,
                propertiesToFetch: ["glucose", "date"]
            )

            guard let dicts = results as? [[String: Any]] else {
                throw CoreDataError.fetchError(function: #function, file: #file)
            }
            return dicts.compactMap { dict in
                guard let date = dict["date"] as? Date,
                      let number = dict["glucose"] as? NSNumber
                else { return nil }
                return GlucoseReading(value: number.intValue, date: date)
            }
        } catch {
            warning(.ui, "Fetching glucose for statistics failed", error: error)
            return []
        }
    }

    static func dailyPercentileStats(
        date: Date,
        readings: [GlucoseReading]
    ) -> GlucoseDailyPercentileStats {
        let glucoseValues = readings.map { Double($0.value) }.sorted()

        guard !glucoseValues.isEmpty else {
            return GlucoseDailyPercentileStats(date: date)
        }

        return GlucoseDailyPercentileStats(
            date: date,
            minimum: glucoseValues.first ?? 0,
            percentile10: StatChartUtils.percentile(0.10, of: glucoseValues),
            percentile25: StatChartUtils.percentile(0.25, of: glucoseValues),
            median: StatChartUtils.percentile(0.5, of: glucoseValues),
            percentile75: StatChartUtils.percentile(0.75, of: glucoseValues),
            percentile90: StatChartUtils.percentile(0.90, of: glucoseValues),
            maximum: glucoseValues.last ?? 0
        )
    }
}
