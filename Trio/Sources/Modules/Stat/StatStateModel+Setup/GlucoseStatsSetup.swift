import CoreData
import Foundation

enum GlucoseBand: CaseIterable, Sendable {
    case veryLow
    case low
    case tight
    case upperMid
    case high
    case veryHigh

    static func classify(_ value: Int, bottom: Int, top: Int, highLimit: Int) -> GlucoseBand {
        if value < 54 { return .veryLow }
        if value < bottom { return .low }
        if value <= top { return .tight }
        if value <= highLimit { return .upperMid }
        if value <= 250 { return .high }

        return .veryHigh
    }
}

/// A thread-safe value type to hold glucose data without Core Data dependencies
struct GlucoseReading: Equatable, Sendable {
    let value: Int
    let date: Date
}

/// Represents statistical data for daily glucose metrics by distribution ranges
struct GlucoseDailyDistributionStats: Identifiable {
    let id = UUID()
    /// The date this data represents
    let date: Date
    /// The time-in-range type used for calculations
    let timeInRangeType: TimeInRangeType
    /// Percentage of glucose readings below 54 mg/dL
    let veryLowPct: Double
    /// Percentage of glucose readings in the [54 – lowLimit] mg/dL range
    let lowPct: Double
    /// Percentage of glucose readings within the tighter control range of [bottomThreshold – topThreshold] mg/dL
    let inSmallRangePct: Double
    let upperMidPct: Double
    var inRangePct: Double { inSmallRangePct + upperMidPct }
    /// Percentage of glucose readings in the (highLimit – 250] mg/dL range
    let highPct: Double
    /// Percentage of glucose readings above 250 mg/dL
    let veryHighPct: Double

    init(
        date: Date,
        timeInRangeType: TimeInRangeType,
        veryLowPct: Double = 0,
        lowPct: Double = 0,
        inSmallRangePct: Double = 0,
        upperMidPct: Double = 0,
        highPct: Double = 0,
        veryHighPct: Double = 0
    ) {
        self.date = date
        self.timeInRangeType = timeInRangeType
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

    /// Pure range-distribution computation shared by Stat and the Home stats banner.
    static func compute(
        date: Date,
        readings: [GlucoseReading],
        highLimit: Decimal,
        timeInRangeType: TimeInRangeType
    ) -> GlucoseDailyDistributionStats {
        let totalReadings = Double(readings.count)

        let grouped = Dictionary(grouping: readings) { reading in
            GlucoseBand.classify(
                reading.value,
                bottom: timeInRangeType.bottomThreshold,
                top: timeInRangeType.topThreshold,
                highLimit: Int(highLimit)
            )
        }

        let veryHighReadings = grouped[.veryHigh]?.count ?? 0
        let highReadings = grouped[.high]?.count ?? 0
        let inSmallRangeReadings = grouped[.tight]?.count ?? 0
        let upperMidReadings = grouped[.upperMid]?.count ?? 0
        let lowReadings = grouped[.low]?.count ?? 0
        let veryLowReadings = grouped[.veryLow]?.count ?? 0

        let shareOf: (Int) -> Double = { totalReadings > 0 ? Double($0) / totalReadings * 100 : 0 }

        return GlucoseDailyDistributionStats(
            date: date,
            timeInRangeType: timeInRangeType,
            veryLowPct: shareOf(veryLowReadings),
            lowPct: shareOf(lowReadings),
            inSmallRangePct: shareOf(inSmallRangeReadings),
            upperMidPct: shareOf(upperMidReadings),
            highPct: shareOf(highReadings),
            veryHighPct: shareOf(veryHighReadings)
        )
    }
}

/// Represents percentile-based statistical data for daily glucose metrics
struct GlucoseDailyPercentileStats: Identifiable {
    let id = UUID()
    /// The date this data represents
    let date: Date
    /// Minimum glucose value
    let minimum: Double
    /// 10th percentile glucose value
    let percentile10: Double
    /// 25th percentile glucose value (lower quartile)
    let percentile25: Double
    /// Median (50th percentile) glucose value
    let median: Double
    /// 75th percentile glucose value (upper quartile)
    let percentile75: Double
    /// 90th percentile glucose value
    let percentile90: Double
    /// Maximum glucose value
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
    /// Performs setup for both percentile and distribution glucose statistics from provided IDs
    ///
    /// This method optimizes performance by:
    /// 1. Computing both percentile and distribution statistics concurrently
    /// 2. Creating lookup caches for both stat types simultaneously
    ///
    /// - Parameter ids: Array of NSManagedObjectIDs for glucose readings
    func setupGlucoseStats(with ids: [NSManagedObjectID]) async {
        // Get dates for the past 90 days
        let dates = getDates()
        let processed = await groupGlucoseReadingsByDay(glucoseIDs: ids)
        glucoseReadingsByDay = processed

        dailyGlucosePercentileStats = dates.map { date in
            createGlucoseDailyPercentileStatsFromReadings(date: date, readings: processed[date, default: []])
        }

        dailyGlucoseDistributionStats = dates.map { date in
            GlucoseDailyDistributionStats.compute(
                date: date, readings: processed[date, default: []], highLimit: highLimit, timeInRangeType: timeInRangeType
            )
        }
    }

    /// Generates an array of dates for the specified number of days
    /// - Parameter daysCount: Number of days to generate
    /// - Returns: Array of dates starting from (today - daysCount) to today
    func getDates() -> [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        return (0 ..< 90).map { dayOffset -> Date in
            calendar.startOfDay(for: calendar.date(byAdding: .day, value: -(89 - dayOffset), to: today)!)
        }
    }

    func glucoseReadings(for ids: [NSManagedObjectID]) async -> [GlucoseReading] {
        let privateContext = CoreDataStack.shared.newTaskContext()

        return await privateContext.perform {
            ids.compactMap { id -> GlucoseReading? in
                do {
                    guard let reading = try privateContext.existingObject(with: id) as? GlucoseStored,
                          let date = reading.date else { return nil }
                    return GlucoseReading(value: Int(reading.glucose), date: date)
                } catch {
                    debugPrint("\(DebuggingIdentifiers.failed) Error fetching glucose: \(error)")
                    return nil
                }
            }
        }
    }

    /// Processes glucose readings for a set of dates in a thread-safe manner
    /// - Parameters:
    ///   - dates: Array of dates to process data for
    ///   - glucoseIDs: Array of NSManagedObjectIDs for glucose readings
    /// - Returns: Array of (date, readings) tuples containing filtered readings for each date
    private func groupGlucoseReadingsByDay(
        glucoseIDs: [NSManagedObjectID]
    ) async -> [Date: [GlucoseReading]] {
        // Handle cancellation early
        if Task.isCancelled {
            return [:]
        }

        let calendar = Calendar.current
        let glucoseReadings = await self.glucoseReadings(for: glucoseIDs)

        return Dictionary(grouping: glucoseReadings) { calendar.startOfDay(for: $0.date) }
    }

    /// Creates a GlucoseDailyPercentileStats object from thread-safe reading values
    /// - Parameters:
    ///   - date: Date for the day
    ///   - readings: Array of thread-safe glucose readings
    /// - Returns: GlucoseDailyPercentileStats object with calculated statistics
    private func createGlucoseDailyPercentileStatsFromReadings(
        date: Date,
        readings: [GlucoseReading]
    ) -> GlucoseDailyPercentileStats {
        let glucoseValues = readings.map { Double($0.value) }.sorted()

        // If no data, return empty data
        guard !glucoseValues.isEmpty else {
            return GlucoseDailyPercentileStats(date: date)
        }

        // Calculate all percentiles concurrently
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
