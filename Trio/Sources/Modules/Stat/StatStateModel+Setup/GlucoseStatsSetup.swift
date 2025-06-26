import CoreData
import Foundation

/// A thread-safe value type to hold glucose data without Core Data dependencies
struct GlucoseReading: Sendable {
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
    /// The original glucose readings
    let readings: [GlucoseStored]
    /// Percentage of glucose readings below 54 mg/dL
    let veryLowPct: Double
    /// Percentage of glucose readings in the [54 – lowLimit] mg/dL range
    let lowPct: Double
    /// Percentage of glucose readings within the tighter control range of [bottomThreshold – topThreshold] mg/dL
    let inSmallRangePct: Double
    /// Percentage of glucose readings within the target range of [bottomThreshold – highLimit] mg/dL
    let inRangePct: Double
    /// Percentage of glucose readings in the (highLimit – 250] mg/dL range
    let highPct: Double
    /// Percentage of glucose readings above 250 mg/dL
    let veryHighPct: Double

    init(
        date: Date,
        timeInRangeType: TimeInRangeType,
        readings: [GlucoseStored] = [GlucoseStored](),
        veryLowPct: Double = 0,
        lowPct: Double = 0,
        inSmallRangePct: Double = 0,
        inRangePct: Double = 0,
        highPct: Double = 0,
        veryHighPct: Double = 0
    ) {
        self.date = date
        self.timeInRangeType = timeInRangeType
        self.readings = readings
        self.veryLowPct = veryLowPct
        self.lowPct = lowPct
        self.inSmallRangePct = inSmallRangePct
        self.inRangePct = inRangePct
        self.highPct = highPct
        self.veryHighPct = veryHighPct
    }
}

/// Represents percentile-based statistical data for daily glucose metrics
struct GlucoseDailyPercentileStats: Identifiable {
    let id = UUID()
    /// The date this data represents
    let date: Date
    /// The original glucose readings
    let readings: [GlucoseStored]
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
        readings: [GlucoseStored] = [GlucoseStored](),
        minimum: Double = 0,
        percentile10: Double = 0,
        percentile25: Double = 0,
        median: Double = 0,
        percentile75: Double = 0,
        percentile90: Double = 0,
        maximum: Double = 0
    ) {
        self.date = date
        self.readings = readings
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

        // Calculate both types of statistics concurrently
        async let percentileStats = calculateDailyPercentileStats(
            for: dates,
            glucoseIDs: ids
        )

        async let distributionStats = calculateDailyDistributionStats(
            for: dates,
            glucoseIDs: ids,
            highLimit: highLimit,
            timeInRangeType: timeInRangeType
        )

        let (pStats, dStats) = await (percentileStats, distributionStats)

        dailyGlucosePercentileStats = pStats
        glucosePercentileCache = Dictionary(
            uniqueKeysWithValues: pStats.map {
                (Calendar.current.startOfDay(for: $0.date), $0)
            }
        )

        dailyGlucoseDistributionStats = dStats
        glucoseDistributionCache = Dictionary(
            uniqueKeysWithValues: dStats.map {
                (Calendar.current.startOfDay(for: $0.date), $0)
            }
        )
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

    /// Processes glucose readings for a set of dates in a thread-safe manner
    /// - Parameters:
    ///   - dates: Array of dates to process data for
    ///   - glucoseIDs: Array of NSManagedObjectIDs for glucose readings
    /// - Returns: Array of (date, readings) tuples containing filtered readings for each date
    private func processGlucoseReadingsForDates(
        _ dates: [Date],
        glucoseIDs: [NSManagedObjectID]
    ) async -> [(date: Date, readings: [GlucoseReading])] {
        let calendar = Calendar.current

        // Handle cancellation early
        if Task.isCancelled {
            return []
        }

        // Extract the thread-safe glucose readings
        let privateContext = CoreDataStack.shared.newTaskContext()

        // Map into Sendable struct
        let glucoseReadings: [GlucoseReading] = await privateContext.perform {
            // Get NSManagedObject on private context and map into GlucoseReading struct
            glucoseIDs.compactMap { id -> GlucoseReading? in
                guard let reading = privateContext.object(with: id) as? GlucoseStored,
                      let date = reading.date else { return nil }
                return GlucoseReading(value: Int(reading.glucose), date: date)
            }
        }

        return await withTaskGroup(of: (date: Date, readings: [GlucoseReading]).self) { group in
            for date in dates {
                group.addTask {
                    let dayStart = calendar.startOfDay(for: date)
                    let dayEnd = calendar.isDateInToday(date) ?
                        Date.now :
                        calendar.date(byAdding: .day, value: 1, to: dayStart)!

                    let filteredReadings = glucoseReadings.filter {
                        $0.date >= dayStart && $0.date < dayEnd
                    }
                    return (date: date, readings: filteredReadings)
                }
            }

            // Collect results
            var results: [(date: Date, readings: [GlucoseReading])] = []
            for await result in group {
                results.append(result)
            }
            return results.sorted { $0.date < $1.date }
        }
    }

    /// Creates a GlucoseDailyDistributionStats object from thread-safe reading values
    /// - Parameters:
    ///   - date: Date for the day
    ///   - readings: Array of thread-safe glucose readings
    ///   - highLimit: Upper limit for target glucose range
    ///   - timeInRangeType: The time-in-range type to use for calculations
    /// - Returns: GlucoseDailyDistributionStats object with calculated statistics
    private func createGlucoseDailyDistributionStatsFromReadings(
        date: Date,
        readings: [GlucoseReading],
        highLimit: Decimal,
        timeInRangeType: TimeInRangeType
    ) -> GlucoseDailyDistributionStats {
        let totalReadings = Double(readings.count)

        // Count readings in each range
        let veryHighReadings = readings.filter { $0.value > 250 }.count
        let highReadings = readings.filter { $0.value > Int(highLimit) && $0.value <= 250 }.count
        let inRangeReadings = readings.filter { $0.value >= timeInRangeType.bottomThreshold && $0.value <= Int(highLimit) }
            .count
        let inSmallRangeReadings = readings
            .filter { $0.value >= timeInRangeType.bottomThreshold && $0.value <= timeInRangeType.topThreshold }.count
        let lowReadings = readings.filter { $0.value < timeInRangeType.bottomThreshold && $0.value >= 54 }.count
        let veryLowReadings = readings.filter { $0.value < 54 }.count

        // Calculate percentages
        let veryLowPct = totalReadings > 0 ? Double(veryLowReadings) / totalReadings * 100 : 0
        let lowPct = totalReadings > 0 ? Double(lowReadings) / totalReadings * 100 : 0
        let inSmallRangePct = totalReadings > 0 ? Double(inSmallRangeReadings) / totalReadings * 100 : 0
        let inRangePct = totalReadings > 0 ? Double(inRangeReadings) / totalReadings * 100 : 0
        let highPct = totalReadings > 0 ? Double(highReadings) / totalReadings * 100 : 0
        let veryHighPct = totalReadings > 0 ? Double(veryHighReadings) / totalReadings * 100 : 0

        // Create empty managed object array since we don't need the actual Core Data objects
        let emptyStoredArray: [GlucoseStored] = []

        return GlucoseDailyDistributionStats(
            date: date,
            timeInRangeType: timeInRangeType,
            readings: emptyStoredArray,
            veryLowPct: veryLowPct,
            lowPct: lowPct,
            inSmallRangePct: inSmallRangePct,
            inRangePct: inRangePct,
            highPct: highPct,
            veryHighPct: veryHighPct
        )
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

        let count = glucoseValues.count

        let calculatePercentile = { (p: Double) -> Double in
            let position = Double(count - 1) * p
            let lower = Int(floor(position))
            let upper = Int(ceil(position))

            if lower == upper {
                return glucoseValues[lower]
            }

            let weight = position - Double(lower)
            return glucoseValues[lower] * (1 - weight) + glucoseValues[upper] * weight
        }

        // Calculate all percentiles concurrently
        return GlucoseDailyPercentileStats(
            date: date,
            readings: [],
            minimum: glucoseValues.first ?? 0,
            percentile10: calculatePercentile(0.10),
            percentile25: calculatePercentile(0.25),
            median: calculatePercentile(0.5),
            percentile75: calculatePercentile(0.75),
            percentile90: calculatePercentile(0.90),
            maximum: glucoseValues.last ?? 0
        )
    }

    func calculateDailyDistributionStats(
        for dates: [Date],
        glucoseIDs: [NSManagedObjectID],
        highLimit: Decimal,
        timeInRangeType: TimeInRangeType
    ) async -> [GlucoseDailyDistributionStats] {
        // Process readings for each date
        let processedData = await processGlucoseReadingsForDates(
            dates,
            glucoseIDs: glucoseIDs
        )

        // Transform into distribution stats
        return processedData.map { date, readings in
            if readings.isEmpty {
                return GlucoseDailyDistributionStats(date: date, timeInRangeType: timeInRangeType)
            } else {
                return createGlucoseDailyDistributionStatsFromReadings(
                    date: date,
                    readings: readings,
                    highLimit: highLimit,
                    timeInRangeType: timeInRangeType
                )
            }
        }
    }

    func calculateDailyPercentileStats(
        for dates: [Date],
        glucoseIDs: [NSManagedObjectID]
    ) async -> [GlucoseDailyPercentileStats] {
        // Process readings for each date
        let processedData = await processGlucoseReadingsForDates(
            dates,
            glucoseIDs: glucoseIDs
        )

        // Transform into percentile stats
        return processedData.map { date, readings in
            if readings.isEmpty {
                return GlucoseDailyPercentileStats(date: date)
            } else {
                return createGlucoseDailyPercentileStatsFromReadings(
                    date: date,
                    readings: readings
                )
            }
        }
    }
}
