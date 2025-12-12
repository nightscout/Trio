import CoreData
import Foundation

/// Exports health data for AI analysis
final class HealthDataExporter {
    private let context: NSManagedObjectContext
    private var healthMetricsService: HealthMetricsService?

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    /// Set the health metrics service for fetching activity, sleep, heart rate, and workout data
    func setHealthMetricsService(_ service: HealthMetricsService) {
        self.healthMetricsService = service
    }

    // MARK: - Data Structures

    struct ExportedData {
        let glucoseReadings: [GlucoseReading]
        let carbEntries: [CarbEntry]
        let bolusEvents: [BolusEvent]
        let loopStates: [LoopState]
        let settings: SettingsSummary
        let statistics: Statistics
        let multiTimeframeStats: MultiTimeframeStatistics?
        let healthMetrics: HealthMetrics?

        struct GlucoseReading {
            let date: Date
            let value: Int
            let direction: String?
            let isManual: Bool
        }

        struct CarbEntry {
            let date: Date
            let carbs: Double
            let fat: Double
            let protein: Double
            let note: String?
        }

        struct BolusEvent {
            let date: Date
            let amount: Decimal
            let isSMB: Bool
            let isExternal: Bool
        }

        /// Loop state snapshot from OrefDetermination - captured every ~5 minutes
        struct LoopState {
            let date: Date
            let glucose: Decimal
            let iob: Decimal
            let cob: Int
            let tempBasalRate: Decimal
            let scheduledBasalRate: Decimal
            let smbDelivered: Decimal
            let eventualBG: Decimal?
            let insulinReq: Decimal
            let reason: String?
        }

        struct SettingsSummary {
            let units: String
            let targetLow: Int
            let targetHigh: Int
            let maxIOB: Decimal
            let maxBolus: Decimal
            let dia: Decimal
            let carbRatioSchedule: [(time: String, ratio: Decimal)]
            let isfSchedule: [(time: String, sensitivity: Decimal)]
            let basalSchedule: [(time: String, rate: Decimal)]
            let targetSchedule: [(time: String, low: Decimal, high: Decimal)]
        }

        struct Statistics {
            let averageGlucose: Int
            let standardDeviation: Double
            let coefficientOfVariation: Double
            let gmi: Double
            let minGlucose: Int
            let maxGlucose: Int
            let timeInRange: Double
            let timeBelowRange: Double
            let timeAboveRange: Double
            let timeVeryLow: Double
            let timeVeryHigh: Double
            let totalCarbs: Double
            let totalBolus: Decimal
            let totalBasal: Decimal
            let readingCount: Int
            let daysOfData: Int
        }

        struct MultiTimeframeStatistics {
            let day1: TimeframeStat?
            let day3: TimeframeStat?
            let day7: TimeframeStat?
            let day14: TimeframeStat?
            let day30: TimeframeStat?
            let day90: TimeframeStat?

            struct TimeframeStat {
                let days: Int
                let averageGlucose: Int
                let standardDeviation: Double
                let coefficientOfVariation: Double
                let gmi: Double
                let timeInRange: Double
                let timeBelowRange: Double
                let timeAboveRange: Double
                let timeVeryLow: Double
                let timeVeryHigh: Double
                let readingCount: Int
            }
        }

        /// Health metrics from wearables (activity, sleep, heart rate, workouts)
        struct HealthMetrics {
            let dailyActivity: [DailyActivitySummary]
            let sleepSummaries: [SleepSummary]
            let hrvData: [HRVDataPoint]
            let heartRateStats: HeartRateStats?
            let workouts: [WorkoutSummary]

            struct DailyActivitySummary {
                let date: Date
                let steps: Int
                let activeCalories: Double
                let exerciseMinutes: Int
            }

            struct SleepSummary {
                let date: Date
                let bedtime: Date
                let wakeTime: Date
                let hoursAsleep: Double
                let sleepEfficiency: Double
                let deepSleepHours: Double?
                let remSleepHours: Double?
            }

            struct HRVDataPoint {
                let date: Date
                let averageSDNN: Double
                let minSDNN: Double
                let maxSDNN: Double
            }

            struct HeartRateStats {
                let averageRestingHR: Int
                let minHR: Int
                let maxHR: Int
                let averageHR: Int
            }

            struct WorkoutSummary {
                let date: Date
                let type: String
                let durationMinutes: Int
                let calories: Double?
                let averageHeartRate: Int?
            }

            var hasAnyData: Bool {
                !dailyActivity.isEmpty || !sleepSummaries.isEmpty || !hrvData.isEmpty ||
                    heartRateStats != nil || !workouts.isEmpty
            }

            static var empty: HealthMetrics {
                HealthMetrics(
                    dailyActivity: [],
                    sleepSummaries: [],
                    hrvData: [],
                    heartRateStats: nil,
                    workouts: []
                )
            }
        }
    }

    // MARK: - Export Methods

    /// Export data for a specified number of days from local CoreData
    func exportData(
        days: Int,
        units: String,
        targetLow: Int,
        targetHigh: Int,
        maxIOB: Decimal,
        maxBolus: Decimal,
        dia: Decimal,
        carbRatioSchedule: [(time: String, ratio: Decimal)],
        isfSchedule: [(time: String, sensitivity: Decimal)],
        basalSchedule: [(time: String, rate: Decimal)],
        targetSchedule: [(time: String, low: Decimal, high: Decimal)],
        healthMetricsSettings: HealthMetricsSettings? = nil
    ) async throws -> ExportedData {
        let startDate = Calendar.current.date(byAdding: .day, value: -days, to: Date())!

        // Fetch all data for the requested period
        let glucoseReadings = try await fetchGlucoseReadings(since: startDate)
        let carbEntries = try await fetchCarbEntries(since: startDate)
        let bolusEvents = try await fetchBolusEvents(since: startDate)
        let loopStates = try await fetchLoopStates(since: startDate)

        // Calculate statistics
        let statistics = calculateStatistics(
            glucose: glucoseReadings,
            carbs: carbEntries,
            boluses: bolusEvents,
            loopStates: loopStates,
            lowThreshold: targetLow,
            highThreshold: targetHigh,
            daysOfData: days
        )

        // Calculate multi-timeframe statistics for longer periods
        let multiStats: ExportedData.MultiTimeframeStatistics? = days >= 7 ? calculateMultiTimeframeStats(
            glucose: glucoseReadings,
            lowThreshold: targetLow,
            highThreshold: targetHigh
        ) : nil

        // Fetch health metrics if service is available and settings are provided
        let healthMetrics = await fetchHealthMetrics(days: days, settings: healthMetricsSettings)

        let settings = ExportedData.SettingsSummary(
            units: units,
            targetLow: targetLow,
            targetHigh: targetHigh,
            maxIOB: maxIOB,
            maxBolus: maxBolus,
            dia: dia,
            carbRatioSchedule: carbRatioSchedule,
            isfSchedule: isfSchedule,
            basalSchedule: basalSchedule,
            targetSchedule: targetSchedule
        )

        return ExportedData(
            glucoseReadings: glucoseReadings,
            carbEntries: carbEntries,
            bolusEvents: bolusEvents,
            loopStates: loopStates,
            settings: settings,
            statistics: statistics,
            multiTimeframeStats: multiStats,
            healthMetrics: healthMetrics
        )
    }

    // MARK: - Private Fetch Methods

    private func fetchGlucoseReadings(since date: Date) async throws -> [ExportedData.GlucoseReading] {
        try await context.perform {
            let request = NSFetchRequest<NSManagedObject>(entityName: "GlucoseStored")
            request.predicate = NSPredicate(format: "date >= %@", date as NSDate)
            request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: true)]

            let results = try self.context.fetch(request)

            return results.compactMap { obj -> ExportedData.GlucoseReading? in
                guard let objDate = obj.value(forKey: "date") as? Date else { return nil }
                let glucose = obj.value(forKey: "glucose") as? Int16 ?? 0
                let direction = obj.value(forKey: "direction") as? String
                let isManual = obj.value(forKey: "isManual") as? Bool ?? false

                return ExportedData.GlucoseReading(
                    date: objDate,
                    value: Int(glucose),
                    direction: direction,
                    isManual: isManual
                )
            }
        }
    }

    private func fetchCarbEntries(since date: Date) async throws -> [ExportedData.CarbEntry] {
        try await context.perform {
            let request = NSFetchRequest<NSManagedObject>(entityName: "CarbEntryStored")
            request.predicate = NSPredicate(format: "date >= %@ AND isFPU == NO", date as NSDate)
            request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: true)]

            let results = try self.context.fetch(request)

            return results.compactMap { obj -> ExportedData.CarbEntry? in
                guard let objDate = obj.value(forKey: "date") as? Date else { return nil }
                let carbs = obj.value(forKey: "carbs") as? Double ?? 0
                let fat = obj.value(forKey: "fat") as? Double ?? 0
                let protein = obj.value(forKey: "protein") as? Double ?? 0
                let note = obj.value(forKey: "note") as? String

                return ExportedData.CarbEntry(
                    date: objDate,
                    carbs: carbs,
                    fat: fat,
                    protein: protein,
                    note: note
                )
            }
        }
    }

    private func fetchBolusEvents(since date: Date) async throws -> [ExportedData.BolusEvent] {
        try await context.perform {
            // Fetch directly from BolusStored entity (like BolusStatsSetup does)
            let request = NSFetchRequest<NSManagedObject>(entityName: "BolusStored")
            // Filter by the parent pumpEvent's timestamp
            request.predicate = NSPredicate(format: "pumpEvent.timestamp >= %@", date as NSDate)
            request.sortDescriptors = [NSSortDescriptor(key: "pumpEvent.timestamp", ascending: true)]

            let results = try self.context.fetch(request)

            return results.compactMap { bolus -> ExportedData.BolusEvent? in
                // Get the timestamp from the related pumpEvent
                guard let pumpEvent = bolus.value(forKey: "pumpEvent") as? NSManagedObject,
                      let timestamp = pumpEvent.value(forKey: "timestamp") as? Date
                else { return nil }

                let amount = (bolus.value(forKey: "amount") as? NSDecimalNumber)?.decimalValue ?? 0
                let isSMB = bolus.value(forKey: "isSMB") as? Bool ?? false
                let isExternal = bolus.value(forKey: "isExternal") as? Bool ?? false

                return ExportedData.BolusEvent(
                    date: timestamp,
                    amount: amount,
                    isSMB: isSMB,
                    isExternal: isExternal
                )
            }
        }
    }

    private func fetchLoopStates(since date: Date) async throws -> [ExportedData.LoopState] {
        try await context.perform {
            let request = NSFetchRequest<NSManagedObject>(entityName: "OrefDetermination")
            request.predicate = NSPredicate(format: "deliverAt >= %@", date as NSDate)
            request.sortDescriptors = [NSSortDescriptor(key: "deliverAt", ascending: true)]

            let results = try self.context.fetch(request)

            return results.compactMap { obj -> ExportedData.LoopState? in
                guard let deliverAt = obj.value(forKey: "deliverAt") as? Date else { return nil }

                let glucose = (obj.value(forKey: "glucose") as? NSDecimalNumber)?.decimalValue ?? 0
                let iob = (obj.value(forKey: "iob") as? NSDecimalNumber)?.decimalValue ?? 0
                let cob = obj.value(forKey: "cob") as? Int16 ?? 0
                let rate = (obj.value(forKey: "rate") as? NSDecimalNumber)?.decimalValue ?? 0
                let scheduledBasal = (obj.value(forKey: "scheduledBasal") as? NSDecimalNumber)?.decimalValue ?? 0
                let smbToDeliver = (obj.value(forKey: "smbToDeliver") as? NSDecimalNumber)?.decimalValue ?? 0
                let eventualBG = (obj.value(forKey: "eventualBG") as? NSDecimalNumber)?.decimalValue
                let insulinReq = (obj.value(forKey: "insulinReq") as? NSDecimalNumber)?.decimalValue ?? 0
                let reason = obj.value(forKey: "reason") as? String

                return ExportedData.LoopState(
                    date: deliverAt,
                    glucose: glucose,
                    iob: iob,
                    cob: Int(cob),
                    tempBasalRate: rate,
                    scheduledBasalRate: scheduledBasal,
                    smbDelivered: smbToDeliver,
                    eventualBG: eventualBG,
                    insulinReq: insulinReq,
                    reason: reason
                )
            }
        }
    }

    // MARK: - Health Metrics Fetching

    private func fetchHealthMetrics(days: Int, settings: HealthMetricsSettings?) async -> ExportedData.HealthMetrics? {
        guard let service = healthMetricsService,
              let settings = settings,
              settings.hasAnyEnabled else {
            return nil
        }

        let endDate = Date()
        let startDate = Calendar.current.date(byAdding: .day, value: -days, to: endDate)!

        var dailyActivity: [ExportedData.HealthMetrics.DailyActivitySummary] = []
        var sleepSummaries: [ExportedData.HealthMetrics.SleepSummary] = []
        var hrvData: [ExportedData.HealthMetrics.HRVDataPoint] = []
        var heartRateStats: ExportedData.HealthMetrics.HeartRateStats?
        var workouts: [ExportedData.HealthMetrics.WorkoutSummary] = []

        // Fetch activity data if enabled
        if settings.enableActivityData {
            do {
                let activities = try await service.fetchDailyActivity(from: startDate, to: endDate)
                dailyActivity = activities.map { activity in
                    ExportedData.HealthMetrics.DailyActivitySummary(
                        date: activity.date,
                        steps: activity.steps,
                        activeCalories: activity.activeCalories,
                        exerciseMinutes: activity.exerciseMinutes
                    )
                }
            } catch {
                // Log but don't fail - activity data is optional
                print("Failed to fetch activity data: \(error)")
            }
        }

        // Fetch sleep data if enabled
        if settings.enableSleepData {
            do {
                let sleepData = try await service.fetchNightSleepSummaries(from: startDate, to: endDate)
                sleepSummaries = sleepData.map { sleep in
                    ExportedData.HealthMetrics.SleepSummary(
                        date: sleep.date,
                        bedtime: sleep.bedtime,
                        wakeTime: sleep.wakeTime,
                        hoursAsleep: sleep.hoursAsleep,
                        sleepEfficiency: sleep.sleepEfficiency,
                        deepSleepHours: sleep.deepSleepDuration.map { $0 / 3600 },
                        remSleepHours: sleep.remSleepDuration.map { $0 / 3600 }
                    )
                }
            } catch {
                print("Failed to fetch sleep data: \(error)")
            }
        }

        // Fetch heart rate and HRV data if enabled
        if settings.enableHeartRateData {
            do {
                // Fetch HRV summaries
                let hrvSummaries = try await service.fetchHRVReadings(from: startDate, to: endDate)

                // Group HRV readings by day and summarize
                let groupedHRV = Dictionary(grouping: hrvSummaries) { reading in
                    Calendar.current.startOfDay(for: reading.date)
                }

                hrvData = groupedHRV.map { date, readings in
                    let sdnnValues = readings.map(\.sdnn)
                    return ExportedData.HealthMetrics.HRVDataPoint(
                        date: date,
                        averageSDNN: sdnnValues.reduce(0, +) / Double(sdnnValues.count),
                        minSDNN: sdnnValues.min() ?? 0,
                        maxSDNN: sdnnValues.max() ?? 0
                    )
                }.sorted { $0.date < $1.date }

                // Fetch heart rate readings for statistics
                let heartRates = try await service.fetchHeartRateReadings(from: startDate, to: endDate)
                let restingHR = try await service.fetchRestingHeartRate(from: startDate, to: endDate)

                if !heartRates.isEmpty {
                    let bpmValues = heartRates.map(\.bpm)
                    let avgResting = restingHR.isEmpty ? nil : restingHR.map(\.bpm).reduce(0, +) / restingHR.count

                    heartRateStats = ExportedData.HealthMetrics.HeartRateStats(
                        averageRestingHR: avgResting ?? 0,
                        minHR: bpmValues.min() ?? 0,
                        maxHR: bpmValues.max() ?? 0,
                        averageHR: bpmValues.reduce(0, +) / bpmValues.count
                    )
                }
            } catch {
                print("Failed to fetch heart rate data: \(error)")
            }
        }

        // Fetch workout data if enabled
        if settings.enableWorkoutData {
            do {
                let workoutSessions = try await service.fetchWorkouts(from: startDate, to: endDate)
                workouts = workoutSessions.map { workout in
                    ExportedData.HealthMetrics.WorkoutSummary(
                        date: workout.start,
                        type: workout.workoutType,
                        durationMinutes: workout.durationMinutes,
                        calories: workout.calories,
                        averageHeartRate: workout.averageHeartRate
                    )
                }
            } catch {
                print("Failed to fetch workout data: \(error)")
            }
        }

        let metrics = ExportedData.HealthMetrics(
            dailyActivity: dailyActivity,
            sleepSummaries: sleepSummaries,
            hrvData: hrvData,
            heartRateStats: heartRateStats,
            workouts: workouts
        )

        return metrics.hasAnyData ? metrics : nil
    }

    // MARK: - Statistics Calculation

    private func calculateStatistics(
        glucose: [ExportedData.GlucoseReading],
        carbs: [ExportedData.CarbEntry],
        boluses: [ExportedData.BolusEvent],
        loopStates: [ExportedData.LoopState],
        lowThreshold: Int,
        highThreshold: Int,
        daysOfData: Int
    ) -> ExportedData.Statistics {
        let glucoseValues = glucose.map(\.value)

        let average = glucoseValues.isEmpty ? 0 : glucoseValues.reduce(0, +) / glucoseValues.count
        let minVal = glucoseValues.min() ?? 0
        let maxVal = glucoseValues.max() ?? 0

        // Standard deviation
        let sd = calculateStandardDeviation(glucoseValues)

        // Coefficient of variation (SD / Mean * 100)
        let cv = average > 0 ? (sd / Double(average)) * 100 : 0

        // GMI (Glucose Management Indicator) = 3.31 + 0.02392 * mean glucose (mg/dL)
        let gmi = 3.31 + 0.02392 * Double(average)

        // Time in ranges
        let veryLow = glucoseValues.filter { $0 < 54 }.count
        let low = glucoseValues.filter { $0 >= 54 && $0 < lowThreshold }.count
        let inRange = glucoseValues.filter { $0 >= lowThreshold && $0 <= highThreshold }.count
        let high = glucoseValues.filter { $0 > highThreshold && $0 <= 250 }.count
        let veryHigh = glucoseValues.filter { $0 > 250 }.count

        let total = Double(glucoseValues.count)
        let tir = total > 0 ? Double(inRange) / total * 100 : 0
        let tbr = total > 0 ? Double(low + veryLow) / total * 100 : 0
        let tar = total > 0 ? Double(high + veryHigh) / total * 100 : 0
        let tvl = total > 0 ? Double(veryLow) / total * 100 : 0
        let tvh = total > 0 ? Double(veryHigh) / total * 100 : 0

        let totalCarbs = carbs.reduce(0.0) { $0 + $1.carbs }
        let totalBolus = boluses.reduce(Decimal(0)) { $0 + $1.amount }

        // Estimate total basal from loop states (temp basal rate * 5min intervals)
        let totalBasal = loopStates.reduce(Decimal(0)) { sum, state in
            sum + (state.tempBasalRate * Decimal(5) / Decimal(60)) // rate * 5min in hours
        }

        return ExportedData.Statistics(
            averageGlucose: average,
            standardDeviation: sd,
            coefficientOfVariation: cv,
            gmi: gmi,
            minGlucose: minVal,
            maxGlucose: maxVal,
            timeInRange: tir,
            timeBelowRange: tbr,
            timeAboveRange: tar,
            timeVeryLow: tvl,
            timeVeryHigh: tvh,
            totalCarbs: totalCarbs,
            totalBolus: totalBolus,
            totalBasal: totalBasal,
            readingCount: glucoseValues.count,
            daysOfData: daysOfData
        )
    }

    private func calculateMultiTimeframeStats(
        glucose: [ExportedData.GlucoseReading],
        lowThreshold: Int,
        highThreshold: Int
    ) -> ExportedData.MultiTimeframeStatistics {
        let now = Date()

        func statsFor(days: Int) -> ExportedData.MultiTimeframeStatistics.TimeframeStat? {
            let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: now)!
            let filtered = glucose.filter { $0.date >= cutoff }

            guard !filtered.isEmpty else { return nil }

            let values = filtered.map(\.value)
            let average = values.reduce(0, +) / values.count
            let sd = calculateStandardDeviation(values)
            let cv = average > 0 ? (sd / Double(average)) * 100 : 0
            let gmi = 3.31 + 0.02392 * Double(average)

            let total = Double(values.count)
            let veryLow = values.filter { $0 < 54 }.count
            let low = values.filter { $0 >= 54 && $0 < lowThreshold }.count
            let inRange = values.filter { $0 >= lowThreshold && $0 <= highThreshold }.count
            let high = values.filter { $0 > highThreshold && $0 <= 250 }.count
            let veryHigh = values.filter { $0 > 250 }.count

            return ExportedData.MultiTimeframeStatistics.TimeframeStat(
                days: days,
                averageGlucose: average,
                standardDeviation: sd,
                coefficientOfVariation: cv,
                gmi: gmi,
                timeInRange: Double(inRange) / total * 100,
                timeBelowRange: Double(low + veryLow) / total * 100,
                timeAboveRange: Double(high + veryHigh) / total * 100,
                timeVeryLow: Double(veryLow) / total * 100,
                timeVeryHigh: Double(veryHigh) / total * 100,
                readingCount: values.count
            )
        }

        return ExportedData.MultiTimeframeStatistics(
            day1: statsFor(days: 1),
            day3: statsFor(days: 3),
            day7: statsFor(days: 7),
            day14: statsFor(days: 14),
            day30: statsFor(days: 30),
            day90: statsFor(days: 90)
        )
    }

    private func calculateStandardDeviation(_ values: [Int]) -> Double {
        guard values.count > 1 else { return 0 }
        let mean = Double(values.reduce(0, +)) / Double(values.count)
        let squaredDiffs = values.map { pow(Double($0) - mean, 2) }
        let variance = squaredDiffs.reduce(0, +) / Double(values.count - 1)
        return sqrt(variance)
    }

    // MARK: - Prompt Formatting

    /// Format data as a prompt for Claude
    func formatForPrompt(_ data: ExportedData, analysisType: AnalysisType) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        dateFormatter.timeStyle = .short

        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "MM/dd HH:mm"

        var prompt = """
        Here is my diabetes data from the last 7 days:

        ⚙️ SETTINGS
        • Units: \(data.settings.units)
        • Target Range: \(data.settings.targetLow)-\(data.settings.targetHigh) \(data.settings.units)
        • Max IOB: \(data.settings.maxIOB) U
        • Max Bolus: \(data.settings.maxBolus) U
        • DIA: \(data.settings.dia) hours

        📋 CARB RATIOS (1 unit insulin per X grams)
        \(formatSchedule(data.settings.carbRatioSchedule.map { "\($0.time): 1:\($0.ratio)" }))

        📋 INSULIN SENSITIVITY FACTORS (1 unit drops BG by X \(data.settings.units))
        \(formatSchedule(data.settings.isfSchedule.map { "\($0.time): \($0.sensitivity)" }))

        📋 BASAL RATES (U/hr)
        \(formatSchedule(data.settings.basalSchedule.map { "\($0.time): \($0.rate) U/hr" }))

        📋 TARGET GLUCOSE RANGES
        \(formatSchedule(data.settings.targetSchedule.map { "\($0.time): \($0.low)-\($0.high) \(data.settings.units)" }))

        📊 STATISTICS (Last 7 Days)
        • Average Glucose: \(data.statistics.averageGlucose) \(data.settings.units)
        • Standard Deviation: \(String(format: "%.1f", data.statistics.standardDeviation)) \(data.settings.units)
        • CV (Coefficient of Variation): \(String(format: "%.1f", data.statistics.coefficientOfVariation))%
        • GMI (Glucose Management Indicator): \(String(format: "%.1f", data.statistics.gmi))%
        • Range: \(data.statistics.minGlucose) - \(data.statistics.maxGlucose) \(data.settings.units)
        • Time in Range (\(data.settings.targetLow)-\(data.settings.targetHigh)): \(String(format: "%.1f", data.statistics.timeInRange))%
        • Time Below Range: \(String(format: "%.1f", data.statistics.timeBelowRange))% (Very Low <54: \(String(format: "%.1f", data.statistics.timeVeryLow))%)
        • Time Above Range: \(String(format: "%.1f", data.statistics.timeAboveRange))% (Very High >250: \(String(format: "%.1f", data.statistics.timeVeryHigh))%)
        • Total Carbs: \(String(format: "%.0f", data.statistics.totalCarbs))g
        • Total Bolus Insulin: \(data.statistics.totalBolus) U
        • Total Basal Insulin: \(String(format: "%.1f", NSDecimalNumber(decimal: data.statistics.totalBasal).doubleValue)) U
        • CGM Readings: \(data.statistics.readingCount)

        """

        switch analysisType {
        case .quick(let settings):
            prompt = formatQuickAnalysisPrompt(data, timeFormatter: timeFormatter, settings: settings)

        case .weeklyReport:
            // Add comprehensive raw data for weekly report
            prompt += """

            📈 RAW LOOP DATA (Last 7 days, ~15 min intervals)
            Format: Time | BG | IOB | COB | TempBasal | SMB
            \(formatLoopStatesCompact(data.loopStates, timeFormatter: timeFormatter, hours: 168, intervalMinutes: 15))

            🍽️ ALL CARB ENTRIES
            \(formatCarbEntries(data.carbEntries, dateFormatter: timeFormatter))

            💉 BOLUS HISTORY
            \(formatBolusEvents(data.bolusEvents, dateFormatter: timeFormatter))

            Please provide a comprehensive weekly report with these sections:

            📊 **Summary**
            - Overall glucose control assessment
            - Key metrics interpretation

            📈 **Pattern Analysis**
            - Time-of-day trends (morning, afternoon, evening, overnight)
            - Post-meal responses
            - Any recurring issues

            ✅ **What's Working Well**
            - Positive observations
            - Good control periods

            ⚠️ **Areas for Improvement**
            - Concerning patterns
            - Missed meals or unlogged carbs

            💡 **Recommendations**
            - Specific setting adjustments (be specific with numbers)
            - Behavioral suggestions
            - Follow-up items to monitor

            Format this as a professional report suitable for sharing with a healthcare provider.
            """

        case .chat:
            // For chat, include recent context
            prompt += """

            📈 RECENT LOOP DATA (Last 6 hours)
            Format: Time | BG | IOB | COB | TempBasal | SMB
            \(formatLoopStatesCompact(data.loopStates, timeFormatter: timeFormatter, hours: 6, intervalMinutes: 10))

            Based on this data, please answer my question.
            """

        case .doctorVisit(let settings):
            prompt = formatDoctorVisitPrompt(data, timeFormatter: timeFormatter, settings: settings)

        case .whyHighLow:
            // Why High/Low uses a different data path via exportDataForHours() and formatWhyHighLowPrompt()
            // This case should not be reached through generatePrompt()
            prompt = "Error: whyHighLow should use exportDataForHours() instead"

        case .claudeOTune(let settings):
            prompt = formatClaudeOTunePrompt(data, settings: settings)
        }

        return prompt
    }

    private func formatQuickAnalysisPrompt(
        _ data: ExportedData,
        timeFormatter: DateFormatter,
        settings: QuickAnalysisSettings
    ) -> String {
        var prompt = """
        # DIABETES DATA FOR QUICK ANALYSIS

        Generated: \(DateFormatter.localizedString(from: Date(), dateStyle: .full, timeStyle: .short))
        Data Period: Last \(settings.days) day\(settings.days > 1 ? "s" : "")

        ---

        """

        // MARK: - Treatment Settings Section
        var hasSettingsSection = false

        if settings.showInsulinSettings || settings.showCarbRatios || settings.showISF ||
           settings.showBasalRates || settings.showTargets {
            prompt += "## ⚙️ CURRENT TREATMENT SETTINGS\n\n"
            hasSettingsSection = true
        }

        if settings.showInsulinSettings {
            prompt += """
            ### Insulin Settings
            • Units: \(data.settings.units)
            • Target Range: \(data.settings.targetLow)-\(data.settings.targetHigh) \(data.settings.units)
            • Insulin Duration of Action (DIA): \(data.settings.dia) hours
            • Maximum IOB: \(data.settings.maxIOB) U
            • Maximum Bolus: \(data.settings.maxBolus) U

            """
        }

        if settings.showCarbRatios {
            prompt += """
            ### Carb Ratios (1 unit insulin per X grams carbs)
            \(formatScheduleVertical(data.settings.carbRatioSchedule.map { "  \($0.time): 1:\($0.ratio)" }))

            """
        }

        if settings.showISF {
            prompt += """
            ### Insulin Sensitivity Factors (1 unit drops BG by X \(data.settings.units))
            \(formatScheduleVertical(data.settings.isfSchedule.map { "  \($0.time): \($0.sensitivity) \(data.settings.units)" }))

            """
        }

        if settings.showBasalRates {
            prompt += """
            ### Basal Rates
            \(formatScheduleVertical(data.settings.basalSchedule.map { "  \($0.time): \($0.rate) U/hr" }))

            """
        }

        if settings.showTargets {
            prompt += """
            ### Target Glucose Ranges
            \(formatScheduleVertical(data.settings.targetSchedule.map { "  \($0.time): \($0.low)-\($0.high) \(data.settings.units)" }))

            """
        }

        if hasSettingsSection {
            prompt += "---\n\n"
        }

        // MARK: - Statistics Section
        if settings.showStatistics {
            prompt += """
            ## 📊 STATISTICS (Last \(settings.days) Day\(settings.days > 1 ? "s" : ""))
            • Average Glucose: \(data.statistics.averageGlucose) \(data.settings.units)
            • Standard Deviation: \(String(format: "%.1f", data.statistics.standardDeviation)) \(data.settings.units)
            • CV (Coefficient of Variation): \(String(format: "%.1f", data.statistics.coefficientOfVariation))%
            • GMI (Glucose Management Indicator): \(String(format: "%.1f", data.statistics.gmi))%
            • Range: \(data.statistics.minGlucose) - \(data.statistics.maxGlucose) \(data.settings.units)
            • Time in Range (\(data.settings.targetLow)-\(data.settings.targetHigh)): \(String(format: "%.1f", data.statistics.timeInRange))%
            • Time Below Range: \(String(format: "%.1f", data.statistics.timeBelowRange))% (Very Low <54: \(String(format: "%.1f", data.statistics.timeVeryLow))%)
            • Time Above Range: \(String(format: "%.1f", data.statistics.timeAboveRange))% (Very High >250: \(String(format: "%.1f", data.statistics.timeVeryHigh))%)
            • Total Carbs: \(String(format: "%.0f", data.statistics.totalCarbs))g
            • Total Bolus Insulin: \(data.statistics.totalBolus) U
            • CGM Readings: \(data.statistics.readingCount)

            ---

            """
        }

        // MARK: - Detailed Data Section
        if settings.showLoopData || settings.showCarbEntries || settings.showBolusHistory {
            prompt += "## 📈 DETAILED DATA\n\n"

            if settings.showLoopData {
                let hoursToShow = min(settings.days * 24, 168) // Cap at 7 days of loop data
                prompt += """
                ### Loop States (BG, IOB, COB, Temp Basal, SMB)
                Format: DateTime | BG | IOB | COB | TempBasal | SMB
                \(formatLoopStatesCompact(data.loopStates, timeFormatter: timeFormatter, hours: hoursToShow, intervalMinutes: 15))

                """
            }

            if settings.showCarbEntries {
                prompt += """
                ### Carb Entries
                \(formatCarbEntries(data.carbEntries, dateFormatter: timeFormatter))

                """
            }

            if settings.showBolusHistory {
                prompt += """
                ### Bolus History
                \(formatBolusEvents(data.bolusEvents, dateFormatter: timeFormatter))

                """
            }

            prompt += "---\n\n"
        }

        // MARK: - Health Metrics Section
        if settings.showHealthMetrics, let healthMetrics = data.healthMetrics, healthMetrics.hasAnyData {
            prompt += formatHealthMetrics(healthMetrics, dateFormatter: timeFormatter)
            prompt += "\n---\n\n"
        }

        // MARK: - AI Analysis Request (Custom Prompt)
        prompt += "## 🤖 AI ANALYSIS REQUEST\n\n"

        if settings.customPrompt.isEmpty {
            // Use default prompt if custom is empty
            var defaultPrompt = """
            Please provide a quick analysis using these sections:
            📊 **Overview** - Brief summary of glucose control
            🔍 **Key Patterns** - Notable trends you observe
            ⚠️ **Concerns** - Any issues needing attention
            💡 **Quick Tip** - One actionable suggestion
            """

            if settings.showHealthMetrics, let healthMetrics = data.healthMetrics, healthMetrics.hasAnyData {
                defaultPrompt += """

            🏃 **Lifestyle Insights** - How activity, sleep, or heart rate patterns may be affecting glucose
            """
            }
            prompt += defaultPrompt
        } else {
            prompt += settings.customPrompt
        }

        return prompt
    }

    private func formatDoctorVisitPrompt(
        _ data: ExportedData,
        timeFormatter: DateFormatter,
        settings: DoctorReportSettings
    ) -> String {
        var prompt = """
        # COMPREHENSIVE DIABETES DATA EXPORT FOR HEALTHCARE PROVIDER REVIEW

        Generated: \(DateFormatter.localizedString(from: Date(), dateStyle: .full, timeStyle: .short))
        Data Period: Last \(settings.days) day\(settings.days > 1 ? "s" : "")

        ---

        """

        // MARK: - Treatment Settings Section
        var hasSettingsSection = false

        if settings.showInsulinSettings || settings.showCarbRatios || settings.showISF ||
           settings.showBasalRates || settings.showTargets {
            prompt += "## ⚙️ CURRENT TREATMENT SETTINGS\n\n"
            hasSettingsSection = true
        }

        if settings.showInsulinSettings {
            prompt += """
            ### Insulin Settings
            • Insulin Duration of Action (DIA): \(data.settings.dia) hours
            • Maximum IOB: \(data.settings.maxIOB) U
            • Maximum Bolus: \(data.settings.maxBolus) U

            """
        }

        if settings.showCarbRatios {
            prompt += """
            ### Carb Ratios (1 unit insulin per X grams carbs)
            \(formatScheduleVertical(data.settings.carbRatioSchedule.map { "  \($0.time): 1:\($0.ratio)" }))

            """
        }

        if settings.showISF {
            prompt += """
            ### Insulin Sensitivity Factors (1 unit drops BG by X \(data.settings.units))
            \(formatScheduleVertical(data.settings.isfSchedule.map { "  \($0.time): \($0.sensitivity) \(data.settings.units)" }))

            """
        }

        if settings.showBasalRates {
            let totalDaily = data.settings.basalSchedule.reduce(0.0) { $0 + NSDecimalNumber(decimal: $1.rate).doubleValue }
            prompt += """
            ### Basal Rates
            \(formatScheduleVertical(data.settings.basalSchedule.map { "  \($0.time): \($0.rate) U/hr" }))
            • Total Daily Basal: \(String(format: "%.2f", totalDaily)) U (if constant)

            """
        }

        if settings.showTargets {
            prompt += """
            ### Target Glucose Ranges
            \(formatScheduleVertical(data.settings.targetSchedule.map { "  \($0.time): \($0.low)-\($0.high) \(data.settings.units)" }))

            """
        }

        if hasSettingsSection {
            prompt += "---\n\n"
        }

        // MARK: - Statistics Section
        if settings.showStatistics {
            prompt += "## 📊 MULTI-TIMEFRAME STATISTICS\n\n"

            if let multi = data.multiTimeframeStats {
                prompt += formatMultiTimeframeTable(multi, units: data.settings.units)
            } else {
                prompt += """
                | Metric | 7 Days |
                |--------|--------|
                | Avg Glucose | \(data.statistics.averageGlucose) \(data.settings.units) |
                | Std Dev | \(String(format: "%.1f", data.statistics.standardDeviation)) |
                | CV | \(String(format: "%.1f", data.statistics.coefficientOfVariation))% |
                | GMI | \(String(format: "%.1f", data.statistics.gmi))% |
                | Time in Range | \(String(format: "%.1f", data.statistics.timeInRange))% |
                | Time Below | \(String(format: "%.1f", data.statistics.timeBelowRange))% |
                | Time Above | \(String(format: "%.1f", data.statistics.timeAboveRange))% |
                | Readings | \(data.statistics.readingCount) |

                """
            }

            prompt += "\n---\n\n"
        }

        // MARK: - Detailed Data Section
        if settings.showLoopData || settings.showCarbEntries || settings.showBolusHistory {
            prompt += "## 📈 DETAILED \(settings.days)-DAY DATA\n\n"

            if settings.showLoopData {
                let hoursToShow = settings.days * 24
                prompt += """
                ### Recent Loop States (Every glucose reading with algorithm data)
                Format: DateTime | BG | IOB | COB | TempBasal | SMB
                \(formatLoopStatesCompact(data.loopStates, timeFormatter: timeFormatter, hours: hoursToShow, intervalMinutes: 5))

                """
            }

            if settings.showCarbEntries {
                prompt += """
                ### Carb Entries
                \(formatCarbEntries(data.carbEntries, dateFormatter: timeFormatter))

                """
            }

            if settings.showBolusHistory {
                prompt += """
                ### Bolus History
                \(formatBolusEvents(data.bolusEvents, dateFormatter: timeFormatter))

                """
            }

            prompt += "---\n\n"
        }

        // MARK: - Health Metrics Section
        if settings.showHealthMetrics, let healthMetrics = data.healthMetrics, healthMetrics.hasAnyData {
            prompt += formatHealthMetrics(healthMetrics, dateFormatter: timeFormatter)
            prompt += "\n---\n\n"
        }

        // MARK: - AI Analysis Request (Custom Prompt)
        prompt += "## 🤖 AI ANALYSIS REQUEST\n\n"

        if settings.customPrompt.isEmpty {
            // Use default prompt if custom is empty
            var defaultPrompt = """
            Please analyze this data and provide a comprehensive report for discussion with my healthcare provider. Include:

            ### 📊 **Executive Summary**
            - Overall diabetes management assessment
            - Key metrics vs targets (TIR goal >70%, TBR <4%, CV <36%)

            ### 📈 **Trend Analysis**
            - Compare metrics across timeframes (improving, stable, or declining)
            - Identify any concerning trends

            ### 🕐 **Time-of-Day Patterns**
            - Morning/dawn phenomenon analysis
            - Post-meal patterns
            - Overnight control
            - Any consistent problem times

            ### ⚙️ **Settings Recommendations**
            - Specific basal rate adjustments (time and amount)
            - Carb ratio changes needed
            - ISF modifications
            - Target range considerations

            ### ⚠️ **Safety Concerns**
            - Hypoglycemia patterns and prevention
            - Severe hyperglycemia events
            - Glycemic variability concerns
            """

            if settings.showHealthMetrics, let healthMetrics = data.healthMetrics, healthMetrics.hasAnyData {
                defaultPrompt += """

            ### 🏃 **Lifestyle Factor Analysis**
            - Impact of physical activity on glucose control
            - Sleep quality correlation with glucose stability
            - Heart rate variability trends and stress indicators
            - Exercise recommendations based on observed patterns
            """
            }

            defaultPrompt += """

            ### 💡 **Discussion Points for Provider**
            - Priority items to address
            - Questions to ask
            - Suggested next steps

            Format this professionally for sharing with an endocrinologist or diabetes care team.
            """
            prompt += defaultPrompt
        } else {
            prompt += settings.customPrompt
        }

        return prompt
    }

    private func formatMultiTimeframeTable(
        _ stats: ExportedData.MultiTimeframeStatistics,
        units: String
    ) -> String {
        var rows: [(String, ExportedData.MultiTimeframeStatistics.TimeframeStat)] = []
        if let s = stats.day1 { rows.append(("1 Day", s)) }
        if let s = stats.day3 { rows.append(("3 Days", s)) }
        if let s = stats.day7 { rows.append(("7 Days", s)) }
        if let s = stats.day14 { rows.append(("14 Days", s)) }
        if let s = stats.day30 { rows.append(("30 Days", s)) }
        if let s = stats.day90 { rows.append(("90 Days", s)) }

        guard !rows.isEmpty else { return "No historical data available" }

        // Build markdown table
        var header = "| Metric |"
        var divider = "|--------|"
        for (label, _) in rows {
            header += " \(label) |"
            divider += "--------|"
        }

        var table = header + "\n" + divider + "\n"

        // Average Glucose
        table += "| Avg Glucose |"
        for (_, s) in rows { table += " \(s.averageGlucose) |" }
        table += "\n"

        // Standard Deviation
        table += "| Std Dev |"
        for (_, s) in rows { table += " \(String(format: "%.1f", s.standardDeviation)) |" }
        table += "\n"

        // CV
        table += "| CV% |"
        for (_, s) in rows { table += " \(String(format: "%.1f", s.coefficientOfVariation))% |" }
        table += "\n"

        // GMI
        table += "| GMI |"
        for (_, s) in rows { table += " \(String(format: "%.1f", s.gmi))% |" }
        table += "\n"

        // Time in Range
        table += "| TIR |"
        for (_, s) in rows { table += " \(String(format: "%.1f", s.timeInRange))% |" }
        table += "\n"

        // Time Below Range
        table += "| TBR |"
        for (_, s) in rows { table += " \(String(format: "%.1f", s.timeBelowRange))% |" }
        table += "\n"

        // Time Above Range
        table += "| TAR |"
        for (_, s) in rows { table += " \(String(format: "%.1f", s.timeAboveRange))% |" }
        table += "\n"

        // Very Low
        table += "| Very Low (<54) |"
        for (_, s) in rows { table += " \(String(format: "%.1f", s.timeVeryLow))% |" }
        table += "\n"

        // Very High (>250)
        table += "| Very High (>250) |"
        for (_, s) in rows { table += " \(String(format: "%.1f", s.timeVeryHigh))% |" }
        table += "\n"

        // Reading Count
        table += "| Readings |"
        for (_, s) in rows { table += " \(s.readingCount) |" }
        table += "\n"

        return table
    }

    private func formatSchedule(_ entries: [String]) -> String {
        if entries.isEmpty {
            return "Not configured"
        }
        return entries.joined(separator: " | ")
    }

    private func formatScheduleVertical(_ entries: [String]) -> String {
        if entries.isEmpty {
            return "  Not configured"
        }
        return entries.joined(separator: "\n")
    }

    private func formatLoopStatesCompact(
        _ states: [ExportedData.LoopState],
        timeFormatter: DateFormatter,
        hours: Int,
        intervalMinutes: Int
    ) -> String {
        let cutoff = Calendar.current.date(byAdding: .hour, value: -hours, to: Date())!
        let filtered = states.filter { $0.date > cutoff }

        if filtered.isEmpty {
            return "No loop data available"
        }

        // Sample at specified intervals
        var sampled: [ExportedData.LoopState] = []
        var lastTime: Date?
        let intervalSeconds = Double(intervalMinutes * 60)

        for state in filtered {
            if let last = lastTime {
                if state.date.timeIntervalSince(last) >= intervalSeconds {
                    sampled.append(state)
                    lastTime = state.date
                }
            } else {
                sampled.append(state)
                lastTime = state.date
            }
        }

        return sampled.map { state in
            let bg = String(format: "%.0f", NSDecimalNumber(decimal: state.glucose).doubleValue)
            let iob = String(format: "%.2f", NSDecimalNumber(decimal: state.iob).doubleValue)
            let tempBasal = String(format: "%.2f", NSDecimalNumber(decimal: state.tempBasalRate).doubleValue)
            let smb = state.smbDelivered > 0 ? String(
                format: "%.2f",
                NSDecimalNumber(decimal: state.smbDelivered).doubleValue
            ) : "-"

            return "\(timeFormatter.string(from: state.date)) | \(bg) | \(iob) | \(state.cob) | \(tempBasal) | \(smb)"
        }.joined(separator: "\n")
    }

    private func formatCarbEntries(_ entries: [ExportedData.CarbEntry], dateFormatter: DateFormatter) -> String {
        if entries.isEmpty {
            return "No carb entries logged"
        }

        return entries.prefix(100).map { entry in
            var str = "\(dateFormatter.string(from: entry.date)) | \(String(format: "%.0f", entry.carbs))g"
            if entry.fat > 0 || entry.protein > 0 {
                str += " (F:\(String(format: "%.0f", entry.fat))g P:\(String(format: "%.0f", entry.protein))g)"
            }
            if let note = entry.note, !note.isEmpty {
                str += " \"\(note)\""
            }
            return str
        }.joined(separator: "\n")
    }

    private func formatBolusEvents(_ events: [ExportedData.BolusEvent], dateFormatter: DateFormatter) -> String {
        if events.isEmpty {
            return "No bolus events"
        }

        // Group by type for cleaner output
        let manual = events.filter { !$0.isSMB && !$0.isExternal }
        let smbs = events.filter { $0.isSMB }
        let external = events.filter { $0.isExternal }

        var output = ""

        if !manual.isEmpty {
            output += "Manual Boluses:\n"
            output += manual.prefix(50).map { event in
                "\(dateFormatter.string(from: event.date)) | \(event.amount) U"
            }.joined(separator: "\n")
        }

        if !smbs.isEmpty {
            if !output.isEmpty { output += "\n\n" }
            let totalSMB = smbs.reduce(Decimal(0)) { $0 + $1.amount }
            output +=
                "SMBs: \(smbs.count) deliveries, \(String(format: "%.2f", NSDecimalNumber(decimal: totalSMB).doubleValue)) U total"
        }

        if !external.isEmpty {
            if !output.isEmpty { output += "\n\n" }
            output += "External/Pen Injections:\n"
            output += external.prefix(20).map { event in
                "\(dateFormatter.string(from: event.date)) | \(event.amount) U"
            }.joined(separator: "\n")
        }

        return output
    }

    // MARK: - Health Metrics Formatting

    private func formatHealthMetrics(_ metrics: ExportedData.HealthMetrics?, dateFormatter: DateFormatter) -> String {
        guard let metrics = metrics, metrics.hasAnyData else {
            return ""
        }

        var output = "\n## 🏃 HEALTH & FITNESS METRICS (from Apple Health)\n\n"

        // Activity Data
        if !metrics.dailyActivity.isEmpty {
            output += "### Daily Activity\n"
            let avgSteps = metrics.dailyActivity.map(\.steps).reduce(0, +) / max(metrics.dailyActivity.count, 1)
            let avgCalories = metrics.dailyActivity.map(\.activeCalories).reduce(0, +) / Double(max(metrics.dailyActivity.count, 1))
            let avgExercise = metrics.dailyActivity.map(\.exerciseMinutes).reduce(0, +) / max(metrics.dailyActivity.count, 1)

            output += "• Average Daily Steps: \(avgSteps)\n"
            output += "• Average Active Calories: \(String(format: "%.0f", avgCalories)) kcal\n"
            output += "• Average Exercise Minutes: \(avgExercise) min\n\n"

            output += "Daily Breakdown:\n"
            let dayFormatter = DateFormatter()
            dayFormatter.dateFormat = "MM/dd (EEE)"
            for activity in metrics.dailyActivity.suffix(14) { // Show last 14 days
                output += "\(dayFormatter.string(from: activity.date)): \(activity.steps) steps | \(String(format: "%.0f", activity.activeCalories)) kcal | \(activity.exerciseMinutes) min exercise\n"
            }
            output += "\n"
        }

        // Sleep Data
        if !metrics.sleepSummaries.isEmpty {
            output += "### Sleep Analysis\n"
            let avgSleepHours = metrics.sleepSummaries.map(\.hoursAsleep).reduce(0, +) / Double(max(metrics.sleepSummaries.count, 1))
            let avgEfficiency = metrics.sleepSummaries.map(\.sleepEfficiency).reduce(0, +) / Double(max(metrics.sleepSummaries.count, 1))

            output += "• Average Sleep Duration: \(String(format: "%.1f", avgSleepHours)) hours\n"
            output += "• Average Sleep Efficiency: \(String(format: "%.0f", avgEfficiency * 100))%\n\n"

            output += "Nightly Breakdown:\n"
            let timeFormatter = DateFormatter()
            timeFormatter.dateFormat = "HH:mm"
            let dayFormatter = DateFormatter()
            dayFormatter.dateFormat = "MM/dd"

            for sleep in metrics.sleepSummaries.suffix(14) { // Show last 14 nights
                var line = "\(dayFormatter.string(from: sleep.date)): \(timeFormatter.string(from: sleep.bedtime))-\(timeFormatter.string(from: sleep.wakeTime)) | \(String(format: "%.1f", sleep.hoursAsleep))h"
                if let deep = sleep.deepSleepHours {
                    line += " | Deep: \(String(format: "%.1f", deep))h"
                }
                if let rem = sleep.remSleepHours {
                    line += " | REM: \(String(format: "%.1f", rem))h"
                }
                output += line + "\n"
            }
            output += "\n"
        }

        // Heart Rate & HRV Data
        if let hrStats = metrics.heartRateStats {
            output += "### Heart Rate\n"
            output += "• Average Resting HR: \(hrStats.averageRestingHR) bpm\n"
            output += "• Average HR: \(hrStats.averageHR) bpm\n"
            output += "• HR Range: \(hrStats.minHR)-\(hrStats.maxHR) bpm\n\n"
        }

        if !metrics.hrvData.isEmpty {
            output += "### Heart Rate Variability (HRV)\n"
            let avgHRV = metrics.hrvData.map(\.averageSDNN).reduce(0, +) / Double(max(metrics.hrvData.count, 1))
            output += "• Average HRV (SDNN): \(String(format: "%.1f", avgHRV)) ms\n\n"

            output += "Daily HRV:\n"
            let dayFormatter = DateFormatter()
            dayFormatter.dateFormat = "MM/dd"
            for hrv in metrics.hrvData.suffix(14) { // Show last 14 days
                output += "\(dayFormatter.string(from: hrv.date)): \(String(format: "%.1f", hrv.averageSDNN)) ms (range: \(String(format: "%.0f", hrv.minSDNN))-\(String(format: "%.0f", hrv.maxSDNN)))\n"
            }
            output += "\n"
        }

        // Workout Data
        if !metrics.workouts.isEmpty {
            output += "### Workouts\n"
            let totalWorkoutMinutes = metrics.workouts.map(\.durationMinutes).reduce(0, +)
            let totalCalories = metrics.workouts.compactMap(\.calories).reduce(0, +)

            output += "• Total Workouts: \(metrics.workouts.count)\n"
            output += "• Total Workout Time: \(totalWorkoutMinutes) min\n"
            output += "• Total Workout Calories: \(String(format: "%.0f", totalCalories)) kcal\n\n"

            // Group by type
            let workoutsByType = Dictionary(grouping: metrics.workouts) { $0.type }
            output += "By Type:\n"
            for (type, workouts) in workoutsByType.sorted(by: { $0.value.count > $1.value.count }) {
                let totalMin = workouts.map(\.durationMinutes).reduce(0, +)
                output += "• \(type): \(workouts.count)x, \(totalMin) min total\n"
            }
            output += "\n"

            output += "Recent Workouts:\n"
            for workout in metrics.workouts.suffix(10) { // Show last 10 workouts
                var line = "\(dateFormatter.string(from: workout.date)): \(workout.type) | \(workout.durationMinutes) min"
                if let calories = workout.calories {
                    line += " | \(String(format: "%.0f", calories)) kcal"
                }
                if let hr = workout.averageHeartRate {
                    line += " | Avg HR: \(hr)"
                }
                output += line + "\n"
            }
        }

        return output
    }

    enum AnalysisType {
        case quick(settings: QuickAnalysisSettings)
        case weeklyReport
        case chat
        case doctorVisit(settings: DoctorReportSettings)
        case whyHighLow(settings: WhyHighLowSettings)
        case claudeOTune(settings: ClaudeOTuneAnalysisSettings)
    }

    struct QuickAnalysisSettings {
        var showCarbRatios: Bool = true
        var showISF: Bool = true
        var showBasalRates: Bool = true
        var showTargets: Bool = true
        var showInsulinSettings: Bool = true
        var showStatistics: Bool = true
        var showLoopData: Bool = true
        var showCarbEntries: Bool = true
        var showBolusHistory: Bool = true
        var showHealthMetrics: Bool = true
        var customPrompt: String = ""
        var days: Int = 7
    }

    struct DoctorReportSettings {
        var showCarbRatios: Bool = true
        var showISF: Bool = true
        var showBasalRates: Bool = true
        var showTargets: Bool = true
        var showInsulinSettings: Bool = true
        var showStatistics: Bool = true
        var showLoopData: Bool = true
        var showCarbEntries: Bool = true
        var showBolusHistory: Bool = true
        var showHealthMetrics: Bool = true
        var customPrompt: String = ""
        var days: Int = 30
    }

    struct WhyHighLowSettings {
        var currentBG: Decimal
        var bgTrend: String // "rising", "falling", "stable", "unknown"
        var currentIOB: Decimal
        var currentCOB: Int
        var isHigh: Bool // true = high, false = low
        var analysisHours: Int = 4
        var customPrompt: String = ""
    }

    struct ClaudeOTuneAnalysisSettings {
        var days: Int = 30
        var includePatternAnalysis: Bool = true
        var includeBasalRecommendations: Bool = true
        var includeISFRecommendations: Bool = true
        var includeCRRecommendations: Bool = true
        var includeHealthMetrics: Bool = true
        var maxAdjustmentPercent: Double = 20.0
        var autosensMax: Double = 1.2
        var autosensMin: Double = 0.7
        var customPrompt: String = ""
    }

    // MARK: - Why High/Low Data Export

    /// Export data for a specified number of hours (for Why High/Low analysis)
    func exportDataForHours(
        hours: Int,
        units: String,
        currentISF: Decimal,
        currentCR: Decimal,
        currentBasalRate: Decimal,
        targetLow: Int,
        targetHigh: Int
    ) async throws -> WhyHighLowData {
        let startDate = Calendar.current.date(byAdding: .hour, value: -hours, to: Date())!

        // Fetch data for the requested period
        let glucoseReadings = try await fetchGlucoseReadings(since: startDate)
        let carbEntries = try await fetchCarbEntries(since: startDate)
        let bolusEvents = try await fetchBolusEvents(since: startDate)
        let loopStates = try await fetchLoopStates(since: startDate)

        return WhyHighLowData(
            glucoseReadings: glucoseReadings,
            carbEntries: carbEntries,
            bolusEvents: bolusEvents,
            loopStates: loopStates,
            currentISF: currentISF,
            currentCR: currentCR,
            currentBasalRate: currentBasalRate,
            targetLow: targetLow,
            targetHigh: targetHigh,
            units: units,
            hours: hours
        )
    }

    struct WhyHighLowData {
        let glucoseReadings: [ExportedData.GlucoseReading]
        let carbEntries: [ExportedData.CarbEntry]
        let bolusEvents: [ExportedData.BolusEvent]
        let loopStates: [ExportedData.LoopState]
        let currentISF: Decimal
        let currentCR: Decimal
        let currentBasalRate: Decimal
        let targetLow: Int
        let targetHigh: Int
        let units: String
        let hours: Int
    }

    /// Format data for Why High/Low analysis prompt
    func formatWhyHighLowPrompt(_ data: WhyHighLowData, settings: WhyHighLowSettings) -> String {
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"

        let dateTimeFormatter = DateFormatter()
        dateTimeFormatter.dateFormat = "MM/dd HH:mm"

        let condition = settings.isHigh ? "HIGH" : "LOW"
        let emoji = settings.isHigh ? "📈" : "📉"

        var prompt = """
        \(emoji) CURRENT STATE: Blood glucose is \(condition)
        • Current BG: \(settings.currentBG) \(data.units) (\(settings.bgTrend))
        • Current IOB: \(String(format: "%.2f", NSDecimalNumber(decimal: settings.currentIOB).doubleValue)) U
        • Current COB: \(settings.currentCOB) g
        • Time: \(timeFormatter.string(from: Date()))

        ⚙️ CURRENT SETTINGS
        • ISF: 1U drops BG by \(settings.isHigh ? data.currentISF : data.currentISF) \(data.units)
        • Carb Ratio: 1U per \(data.currentCR) g
        • Basal Rate: \(data.currentBasalRate) U/hr
        • Target Range: \(data.targetLow)-\(data.targetHigh) \(data.units)

        📊 LAST \(data.hours) HOURS OF DATA

        """

        // Add glucose readings (every reading)
        if !data.glucoseReadings.isEmpty {
            prompt += "\n🩸 GLUCOSE READINGS\n"
            for reading in data.glucoseReadings.suffix(50) { // Last 50 readings max
                let directionArrow = reading.direction ?? ""
                prompt += "\(timeFormatter.string(from: reading.date)): \(reading.value) \(data.units) \(directionArrow)\n"
            }
        }

        // Add carb entries
        if !data.carbEntries.isEmpty {
            prompt += "\n🍽️ CARB ENTRIES\n"
            for entry in data.carbEntries {
                var line = "\(dateTimeFormatter.string(from: entry.date)): \(Int(entry.carbs))g"
                if let note = entry.note, !note.isEmpty {
                    line += " (\(note))"
                }
                prompt += line + "\n"
            }
        } else {
            prompt += "\n🍽️ CARB ENTRIES: None in this period\n"
        }

        // Add bolus events
        if !data.bolusEvents.isEmpty {
            prompt += "\n💉 BOLUSES\n"
            for bolus in data.bolusEvents {
                let type = bolus.isSMB ? "SMB" : "Bolus"
                prompt += "\(dateTimeFormatter.string(from: bolus.date)): \(bolus.amount)U (\(type))\n"
            }
        } else {
            prompt += "\n💉 BOLUSES: None in this period\n"
        }

        // Add loop states (algorithm decisions)
        if !data.loopStates.isEmpty {
            prompt += "\n🔄 LOOP ALGORITHM DECISIONS (sampled)\n"
            prompt += "Time | BG | IOB | COB | TempBasal | SMB\n"

            // Sample every 3rd entry to keep prompt manageable
            let sampledStates = data.loopStates.enumerated().compactMap { index, state in
                index % 3 == 0 ? state : nil
            }

            for state in sampledStates.suffix(20) { // Max 20 entries
                let smb = state.smbDelivered > 0 ? "\(state.smbDelivered)U" : "-"
                prompt += "\(timeFormatter.string(from: state.date)) | \(state.glucose) | \(String(format: "%.2f", NSDecimalNumber(decimal: state.iob).doubleValue))U | \(state.cob)g | \(state.tempBasalRate)U/hr | \(smb)\n"
            }
        }

        // Add the analysis request
        prompt += "\n---\n\n"

        if !settings.customPrompt.isEmpty {
            prompt += settings.customPrompt
        } else {
            prompt += """
            Please analyze why my blood glucose is currently \(condition.lowercased()).

            Provide:
            1. **Probable Cause**: The most likely reason (be specific about timing and amounts)
            2. **Contributing Factors**: Any secondary factors
            3. **Suggestion**: A conservative recommendation if appropriate

            Keep the response concise and actionable. Focus on the most likely explanation.
            """
        }

        return prompt
    }

    // MARK: - Claude-o-Tune Profile Optimization

    /// Format data for Claude-o-Tune profile optimization analysis
    func formatClaudeOTunePrompt(_ data: ExportedData, settings: ClaudeOTuneAnalysisSettings) -> String {
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "MM/dd HH:mm"

        var prompt = """
        # CLAUDE-O-TUNE PROFILE OPTIMIZATION REQUEST

        Generated: \(DateFormatter.localizedString(from: Date(), dateStyle: .full, timeStyle: .short))
        Analysis Period: Last \(settings.days) days

        ## SAFETY CONSTRAINTS
        - Maximum adjustment per recommendation: \(String(format: "%.0f", settings.maxAdjustmentPercent))%
        - Autosens Max (max sensitivity multiplier): \(String(format: "%.2f", settings.autosensMax))
        - Autosens Min (min sensitivity multiplier): \(String(format: "%.2f", settings.autosensMin))

        ---

        ## ⚙️ CURRENT PROFILE SETTINGS

        ### Units
        • Glucose Units: \(data.settings.units)
        • Target Range: \(data.settings.targetLow)-\(data.settings.targetHigh) \(data.settings.units)

        ### Insulin Settings
        • Duration of Insulin Action (DIA): \(data.settings.dia) hours
        • Maximum IOB: \(data.settings.maxIOB) U
        • Maximum Bolus: \(data.settings.maxBolus) U

        """

        // Add basal rates
        if settings.includeBasalRecommendations {
            prompt += """

            ### Current Basal Rates (U/hr)
            """
            for entry in data.settings.basalSchedule {
                prompt += "\n• \(entry.time): \(entry.rate) U/hr"
            }
            let totalBasal = data.settings.basalSchedule.reduce(Decimal(0)) { sum, entry in
                // Approximate daily total assuming each rate applies until next change
                sum + entry.rate
            }
            prompt += "\n• (Approximate daily basal if rates were constant: \(String(format: "%.2f", NSDecimalNumber(decimal: totalBasal).doubleValue)) U)"
        }

        // Add ISF schedule
        if settings.includeISFRecommendations {
            prompt += """

            ### Current Insulin Sensitivity Factors (1U drops BG by X \(data.settings.units))
            """
            for entry in data.settings.isfSchedule {
                prompt += "\n• \(entry.time): \(entry.sensitivity) \(data.settings.units)"
            }
        }

        // Add CR schedule
        if settings.includeCRRecommendations {
            prompt += """

            ### Current Carb Ratios (1U insulin per X grams)
            """
            for entry in data.settings.carbRatioSchedule {
                prompt += "\n• \(entry.time): 1:\(entry.ratio)"
            }
        }

        // Add target schedule
        prompt += """

        ### Target Glucose Ranges
        """
        for entry in data.settings.targetSchedule {
            prompt += "\n• \(entry.time): \(entry.low)-\(entry.high) \(data.settings.units)"
        }

        // Add comprehensive statistics
        prompt += """

        ---

        ## 📊 GLUCOSE STATISTICS (Last \(settings.days) Days)

        ### Overview
        • Average Glucose: \(data.statistics.averageGlucose) \(data.settings.units)
        • Standard Deviation: \(String(format: "%.1f", data.statistics.standardDeviation)) \(data.settings.units)
        • Coefficient of Variation (CV): \(String(format: "%.1f", data.statistics.coefficientOfVariation))%
        • GMI (estimated A1C): \(String(format: "%.1f", data.statistics.gmi))%
        • Range: \(data.statistics.minGlucose) - \(data.statistics.maxGlucose) \(data.settings.units)

        ### Time in Range Breakdown
        • Time in Range (\(data.settings.targetLow)-\(data.settings.targetHigh)): \(String(format: "%.1f", data.statistics.timeInRange))%
        • Time Below Range (<\(data.settings.targetLow)): \(String(format: "%.1f", data.statistics.timeBelowRange))%
        • Time Very Low (<54): \(String(format: "%.1f", data.statistics.timeVeryLow))%
        • Time Above Range (>\(data.settings.targetHigh)): \(String(format: "%.1f", data.statistics.timeAboveRange))%
        • Time Very High (>250): \(String(format: "%.1f", data.statistics.timeVeryHigh))%

        ### Insulin & Carbs Summary
        • Total Carbs: \(String(format: "%.0f", data.statistics.totalCarbs))g
        • Total Bolus Insulin: \(data.statistics.totalBolus) U
        • Total Basal Insulin (estimated): \(String(format: "%.1f", NSDecimalNumber(decimal: data.statistics.totalBasal).doubleValue)) U
        • CGM Readings: \(data.statistics.readingCount)
        • Days of Data: \(data.statistics.daysOfData)

        """

        // Add multi-timeframe statistics if available
        if let multiStats = data.multiTimeframeStats {
            prompt += """

        ### Multi-Timeframe Comparison
        """
            prompt += formatMultiTimeframeForClaudeOTune(multiStats, units: data.settings.units)
        }

        // Add pattern analysis data
        if settings.includePatternAnalysis {
            prompt += """

        ---

        ## 📈 DETAILED GLUCOSE DATA FOR PATTERN ANALYSIS

        ### Loop States (Every 15 minutes)
        Format: DateTime | BG | IOB | COB | TempBasal | SMB
        """
            let hoursToShow = min(settings.days * 24, 168) // Cap at 7 days of detailed data
            prompt += "\n\(formatLoopStatesCompact(data.loopStates, timeFormatter: timeFormatter, hours: hoursToShow, intervalMinutes: 15))"

            prompt += """

        ### Carb Entries
        """
            prompt += "\n\(formatCarbEntries(data.carbEntries, dateFormatter: timeFormatter))"

            prompt += """

        ### Bolus History
        """
            prompt += "\n\(formatBolusEvents(data.bolusEvents, dateFormatter: timeFormatter))"
        }

        // Add health metrics data if available
        if settings.includeHealthMetrics, let healthMetrics = data.healthMetrics, healthMetrics.hasAnyData {
            prompt += formatHealthMetrics(healthMetrics, dateFormatter: timeFormatter)
        }

        // Add the analysis request
        prompt += """

        ---

        ## 🤖 ANALYSIS REQUEST

        """

        if !settings.customPrompt.isEmpty {
            prompt += settings.customPrompt
        } else {
            var analysisPrompt = """
        Please analyze my \(settings.days)-day diabetes data and provide profile optimization recommendations.

        Focus on:
        1. **Pattern Detection**: Identify recurring glucose patterns (dawn phenomenon, post-meal spikes, overnight trends)
        2. **Basal Rate Analysis**: Are there times when basal rates are too high (causing lows) or too low (causing highs)?
        3. **ISF Analysis**: Is my insulin sensitivity factor accurate throughout the day?
        4. **Carb Ratio Analysis**: Do my carb ratios need adjustment for different meals/times?
        5. **Safety Review**: Flag any concerning patterns (frequent hypos, severe highs)
        """

            // Add health metrics analysis instructions if data is available
            if settings.includeHealthMetrics, let healthMetrics = data.healthMetrics, healthMetrics.hasAnyData {
                analysisPrompt += """

        6. **Lifestyle Correlation Analysis**: Analyze how my health metrics correlate with glucose patterns:
           - **Exercise Impact**: How do workouts and daily activity levels affect my glucose control?
           - **Sleep Quality**: Are there patterns between sleep quality/duration and next-day glucose stability?
           - **HRV Trends**: Does HRV (stress/recovery indicator) correlate with insulin sensitivity changes?
           - **Activity Patterns**: On high vs low activity days, are there noticeable glucose differences?
        """
            }

            analysisPrompt += """

        IMPORTANT CONSTRAINTS:
        - Keep all recommended changes within \(String(format: "%.0f", settings.maxAdjustmentPercent))% of current values
        - Prioritize safety over optimization
        - Recommend gradual changes, not aggressive adjustments
        - This is ADVISORY only - I will review with my healthcare provider before making changes

        Respond with a JSON object following the specified output format.
        """
            prompt += analysisPrompt
        }

        return prompt
    }

    private func formatMultiTimeframeForClaudeOTune(
        _ stats: ExportedData.MultiTimeframeStatistics,
        units: String
    ) -> String {
        var output = ""

        let timeframes: [(String, ExportedData.MultiTimeframeStatistics.TimeframeStat?)] = [
            ("1 Day", stats.day1),
            ("3 Days", stats.day3),
            ("7 Days", stats.day7),
            ("14 Days", stats.day14),
            ("30 Days", stats.day30),
            ("90 Days", stats.day90)
        ]

        for (label, stat) in timeframes {
            if let s = stat {
                output += """

        #### \(label)
        • Avg: \(s.averageGlucose) \(units) | CV: \(String(format: "%.1f", s.coefficientOfVariation))% | TIR: \(String(format: "%.1f", s.timeInRange))% | TBR: \(String(format: "%.1f", s.timeBelowRange))% | TAR: \(String(format: "%.1f", s.timeAboveRange))%
        """
            }
        }

        return output
    }
}
