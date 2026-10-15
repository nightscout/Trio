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
            veryLowPct: shareOf(veryLowReadings),
            lowPct: shareOf(lowReadings),
            inSmallRangePct: shareOf(inSmallRangeReadings),
            upperMidPct: shareOf(upperMidReadings),
            highPct: shareOf(highReadings),
            veryHighPct: shareOf(veryHighReadings)
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
                bottom: timeInRangeType.bottomThreshold,
                top: timeInRangeType.topThreshold,
                highLimit: Int(highLimit)
            )

            await MainActor.run {
                self.glucoseFromPersistence = readings
                self.hourlyStats = hourly
                self.glucoseRangeStats = ranges
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
                    date: group.key, readings: group.value, highLimit: highLimit, timeInRangeType: timeInRangeType
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
            debug(.default, "\(DebuggingIdentifiers.failed) Error fetching glucose for stats: \(error)")
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
