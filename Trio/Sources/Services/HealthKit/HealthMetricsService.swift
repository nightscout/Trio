import Combine
import Foundation
import HealthKit
import Swinject

protocol HealthMetricsService {
    /// Check if HealthKit is available on this device
    var isAvailable: Bool { get }

    /// Request permissions for extended health metrics
    func requestPermissions() async -> Bool

    /// Fetch daily steps for a date range
    func fetchDailySteps(from startDate: Date, to endDate: Date) async throws -> [DailySteps]

    /// Fetch daily activity summary (steps, calories, exercise minutes)
    func fetchDailyActivity(from startDate: Date, to endDate: Date) async throws -> [DailyActivity]

    /// Fetch heart rate readings for a date range
    func fetchHeartRateReadings(from startDate: Date, to endDate: Date) async throws -> [HeartRateReading]

    /// Fetch resting heart rate for a date range
    func fetchRestingHeartRate(from startDate: Date, to endDate: Date) async throws -> [HeartRateReading]

    /// Fetch HRV readings for a date range
    func fetchHRVReadings(from startDate: Date, to endDate: Date) async throws -> [HRVReading]

    /// Fetch sleep sessions for a date range
    func fetchSleepSessions(from startDate: Date, to endDate: Date) async throws -> [SleepSession]

    /// Fetch nightly sleep summaries for a date range
    func fetchNightSleepSummaries(from startDate: Date, to endDate: Date) async throws -> [NightSleepSummary]

    /// Fetch workout sessions for a date range
    func fetchWorkouts(from startDate: Date, to endDate: Date) async throws -> [WorkoutSession]

    /// Fetch comprehensive health metrics export for AI analysis
    func fetchHealthMetricsExport(from startDate: Date, to endDate: Date, settings: HealthMetricsSettings) async throws
        -> HealthMetricsExport
}

final class BaseHealthMetricsService: HealthMetricsService, Injectable {
    @Injected() private var healthKitStore: HKHealthStore!
    @Injected() private var settingsManager: SettingsManager!

    var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    init(resolver: Resolver) {
        injectServices(resolver)
        debug(.service, "HealthMetricsService initialized")
    }

    func requestPermissions() async -> Bool {
        guard isAvailable else { return false }

        let typesToRead: Set<HKObjectType> = [
            HKObjectType.quantityType(forIdentifier: .stepCount)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: .appleExerciseTime)!,
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.quantityType(forIdentifier: .restingHeartRate)!,
            HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!,
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
            HKObjectType.workoutType()
        ]

        do {
            try await healthKitStore.requestAuthorization(toShare: [], read: typesToRead)
            debug(.service, "Health metrics permissions granted")
            return true
        } catch {
            warning(.service, "Failed to request health metrics permissions: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Steps

    func fetchDailySteps(from startDate: Date, to endDate: Date) async throws -> [DailySteps] {
        guard let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) else {
            throw HealthMetricsError.typeNotAvailable
        }

        let predicate = HKQuery.predicateForSamples(
            withStart: startDate,
            end: endDate,
            options: .strictStartDate
        )

        var interval = DateComponents()
        interval.day = 1

        let anchorDate = Calendar.current.startOfDay(for: startDate)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: stepType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum,
                anchorDate: anchorDate,
                intervalComponents: interval
            )

            query.initialResultsHandler = { _, results, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                var dailySteps: [DailySteps] = []
                results?.enumerateStatistics(from: startDate, to: endDate) { stats, _ in
                    let steps = stats.sumQuantity()?.doubleValue(for: .count()) ?? 0
                    dailySteps.append(DailySteps(
                        date: stats.startDate,
                        count: Int(steps)
                    ))
                }
                continuation.resume(returning: dailySteps)
            }

            self.healthKitStore.execute(query)
        }
    }

    // MARK: - Daily Activity

    func fetchDailyActivity(from startDate: Date, to endDate: Date) async throws -> [DailyActivity] {
        async let steps = fetchDailySteps(from: startDate, to: endDate)
        async let calories = fetchDailyActiveCalories(from: startDate, to: endDate)
        async let exercise = fetchDailyExerciseMinutes(from: startDate, to: endDate)

        let stepsData = try await steps
        let caloriesData = try await calories
        let exerciseData = try await exercise

        // Merge data by date
        var activityByDate: [Date: DailyActivity] = [:]

        for step in stepsData {
            let dayStart = Calendar.current.startOfDay(for: step.date)
            activityByDate[dayStart] = DailyActivity(
                date: dayStart,
                steps: step.count,
                activeCalories: 0,
                exerciseMinutes: 0
            )
        }

        for cal in caloriesData {
            let dayStart = Calendar.current.startOfDay(for: cal.date)
            if let existing = activityByDate[dayStart] {
                activityByDate[dayStart] = DailyActivity(
                    id: existing.id,
                    date: dayStart,
                    steps: existing.steps,
                    activeCalories: cal.calories,
                    exerciseMinutes: existing.exerciseMinutes
                )
            } else {
                activityByDate[dayStart] = DailyActivity(
                    date: dayStart,
                    steps: 0,
                    activeCalories: cal.calories,
                    exerciseMinutes: 0
                )
            }
        }

        for ex in exerciseData {
            let dayStart = Calendar.current.startOfDay(for: ex.date)
            if let existing = activityByDate[dayStart] {
                activityByDate[dayStart] = DailyActivity(
                    id: existing.id,
                    date: dayStart,
                    steps: existing.steps,
                    activeCalories: existing.activeCalories,
                    exerciseMinutes: ex.minutes
                )
            } else {
                activityByDate[dayStart] = DailyActivity(
                    date: dayStart,
                    steps: 0,
                    activeCalories: 0,
                    exerciseMinutes: ex.minutes
                )
            }
        }

        return activityByDate.values.sorted { $0.date < $1.date }
    }

    private struct DailyCalories {
        let date: Date
        let calories: Double
    }

    private struct DailyExercise {
        let date: Date
        let minutes: Int
    }

    private func fetchDailyActiveCalories(from startDate: Date, to endDate: Date) async throws -> [DailyCalories] {
        guard let calorieType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else {
            throw HealthMetricsError.typeNotAvailable
        }

        let predicate = HKQuery.predicateForSamples(
            withStart: startDate,
            end: endDate,
            options: .strictStartDate
        )

        var interval = DateComponents()
        interval.day = 1

        let anchorDate = Calendar.current.startOfDay(for: startDate)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: calorieType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum,
                anchorDate: anchorDate,
                intervalComponents: interval
            )

            query.initialResultsHandler = { _, results, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                var dailyCalories: [DailyCalories] = []
                results?.enumerateStatistics(from: startDate, to: endDate) { stats, _ in
                    let calories = stats.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
                    dailyCalories.append(DailyCalories(date: stats.startDate, calories: calories))
                }
                continuation.resume(returning: dailyCalories)
            }

            self.healthKitStore.execute(query)
        }
    }

    private func fetchDailyExerciseMinutes(from startDate: Date, to endDate: Date) async throws -> [DailyExercise] {
        guard let exerciseType = HKQuantityType.quantityType(forIdentifier: .appleExerciseTime) else {
            throw HealthMetricsError.typeNotAvailable
        }

        let predicate = HKQuery.predicateForSamples(
            withStart: startDate,
            end: endDate,
            options: .strictStartDate
        )

        var interval = DateComponents()
        interval.day = 1

        let anchorDate = Calendar.current.startOfDay(for: startDate)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: exerciseType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum,
                anchorDate: anchorDate,
                intervalComponents: interval
            )

            query.initialResultsHandler = { _, results, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                var dailyExercise: [DailyExercise] = []
                results?.enumerateStatistics(from: startDate, to: endDate) { stats, _ in
                    let minutes = stats.sumQuantity()?.doubleValue(for: .minute()) ?? 0
                    dailyExercise.append(DailyExercise(date: stats.startDate, minutes: Int(minutes)))
                }
                continuation.resume(returning: dailyExercise)
            }

            self.healthKitStore.execute(query)
        }
    }

    // MARK: - Heart Rate

    func fetchHeartRateReadings(from startDate: Date, to endDate: Date) async throws -> [HeartRateReading] {
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            throw HealthMetricsError.typeNotAvailable
        }

        let predicate = HKQuery.predicateForSamples(
            withStart: startDate,
            end: endDate,
            options: .strictStartDate
        )

        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: heartRateType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                let readings = (samples as? [HKQuantitySample])?.map { sample in
                    HeartRateReading(
                        date: sample.startDate,
                        bpm: Int(sample.quantity.doubleValue(for: HKUnit(from: "count/min"))),
                        source: sample.sourceRevision.source.name
                    )
                } ?? []

                continuation.resume(returning: readings)
            }

            self.healthKitStore.execute(query)
        }
    }

    func fetchRestingHeartRate(from startDate: Date, to endDate: Date) async throws -> [HeartRateReading] {
        guard let restingHRType = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) else {
            throw HealthMetricsError.typeNotAvailable
        }

        let predicate = HKQuery.predicateForSamples(
            withStart: startDate,
            end: endDate,
            options: .strictStartDate
        )

        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: restingHRType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                let readings = (samples as? [HKQuantitySample])?.map { sample in
                    HeartRateReading(
                        date: sample.startDate,
                        bpm: Int(sample.quantity.doubleValue(for: HKUnit(from: "count/min"))),
                        context: .resting,
                        source: sample.sourceRevision.source.name
                    )
                } ?? []

                continuation.resume(returning: readings)
            }

            self.healthKitStore.execute(query)
        }
    }

    // MARK: - HRV

    func fetchHRVReadings(from startDate: Date, to endDate: Date) async throws -> [HRVReading] {
        guard let hrvType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else {
            throw HealthMetricsError.typeNotAvailable
        }

        let predicate = HKQuery.predicateForSamples(
            withStart: startDate,
            end: endDate,
            options: .strictStartDate
        )

        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: hrvType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                let readings = (samples as? [HKQuantitySample])?.map { sample in
                    HRVReading(
                        date: sample.startDate,
                        sdnn: sample.quantity.doubleValue(for: HKUnit.secondUnit(with: .milli)),
                        source: sample.sourceRevision.source.name
                    )
                } ?? []

                continuation.resume(returning: readings)
            }

            self.healthKitStore.execute(query)
        }
    }

    // MARK: - Sleep

    func fetchSleepSessions(from startDate: Date, to endDate: Date) async throws -> [SleepSession] {
        guard let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else {
            throw HealthMetricsError.typeNotAvailable
        }

        let predicate = HKQuery.predicateForSamples(
            withStart: startDate,
            end: endDate,
            options: .strictStartDate
        )

        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                let sessions = (samples as? [HKCategorySample])?.compactMap { sample -> SleepSession? in
                    guard let stage = SleepStage(rawValue: sample.value) else { return nil }
                    return SleepSession(
                        start: sample.startDate,
                        end: sample.endDate,
                        stage: stage,
                        source: sample.sourceRevision.source.name
                    )
                } ?? []

                continuation.resume(returning: sessions)
            }

            self.healthKitStore.execute(query)
        }
    }

    func fetchNightSleepSummaries(from startDate: Date, to endDate: Date) async throws -> [NightSleepSummary] {
        let sessions = try await fetchSleepSessions(from: startDate, to: endDate)

        // Group sessions by night (sessions ending on the same day)
        var sessionsByNight: [Date: [SleepSession]] = [:]

        for session in sessions {
            let wakeDay = Calendar.current.startOfDay(for: session.end)
            if sessionsByNight[wakeDay] == nil {
                sessionsByNight[wakeDay] = []
            }
            sessionsByNight[wakeDay]?.append(session)
        }

        // Create summaries for each night
        var summaries: [NightSleepSummary] = []

        for (wakeDay, nightSessions) in sessionsByNight {
            guard !nightSessions.isEmpty else { continue }

            let sortedSessions = nightSessions.sorted { $0.start < $1.start }
            let bedtime = sortedSessions.first?.start ?? wakeDay
            let wakeTime = sortedSessions.last?.end ?? wakeDay

            var totalAsleep: TimeInterval = 0
            var totalAwake: TimeInterval = 0
            var deepSleep: TimeInterval = 0
            var remSleep: TimeInterval = 0
            var coreSleep: TimeInterval = 0

            for session in sortedSessions {
                switch session.stage {
                case .asleepUnspecified, .asleepCore:
                    totalAsleep += session.duration
                    coreSleep += session.duration
                case .asleepDeep:
                    totalAsleep += session.duration
                    deepSleep += session.duration
                case .asleepREM:
                    totalAsleep += session.duration
                    remSleep += session.duration
                case .awake:
                    totalAwake += session.duration
                case .inBed:
                    break // Don't count as sleep or awake
                }
            }

            let totalDuration = wakeTime.timeIntervalSince(bedtime)

            summaries.append(NightSleepSummary(
                date: wakeDay,
                bedtime: bedtime,
                wakeTime: wakeTime,
                totalDuration: totalDuration,
                timeAsleep: totalAsleep,
                timeAwake: totalAwake,
                deepSleepDuration: deepSleep > 0 ? deepSleep : nil,
                remSleepDuration: remSleep > 0 ? remSleep : nil,
                coreSleepDuration: coreSleep > 0 ? coreSleep : nil
            ))
        }

        return summaries.sorted { $0.date < $1.date }
    }

    // MARK: - Workouts

    func fetchWorkouts(from startDate: Date, to endDate: Date) async throws -> [WorkoutSession] {
        let predicate = HKQuery.predicateForSamples(
            withStart: startDate,
            end: endDate,
            options: .strictStartDate
        )

        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKWorkoutType.workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                let workouts = (samples as? [HKWorkout])?.map { workout in
                    WorkoutSession(
                        workoutType: workout.workoutActivityType.displayName,
                        start: workout.startDate,
                        end: workout.endDate,
                        duration: workout.duration,
                        calories: workout.totalEnergyBurned?.doubleValue(for: .kilocalorie()),
                        distance: workout.totalDistance?.doubleValue(for: .meter()),
                        source: workout.sourceRevision.source.name
                    )
                } ?? []

                continuation.resume(returning: workouts)
            }

            self.healthKitStore.execute(query)
        }
    }

    // MARK: - Comprehensive Export

    func fetchHealthMetricsExport(
        from startDate: Date,
        to endDate: Date,
        settings: HealthMetricsSettings
    ) async throws -> HealthMetricsExport {
        var dailySteps: [DailySteps] = []
        var totalActiveCalories: Double = 0
        var restingHR: Int?
        var avgHR: Int?
        var minHR: Int?
        var maxHR: Int?
        var hrvSummaries: [DailyHRVSummary] = []
        var avgHRV: Double?
        var hrvTrend: TrendDirection?
        var sleepSummaries: [NightSleepSummary] = []
        var workouts: [WorkoutSession] = []

        // Fetch activity data if enabled
        if settings.enableActivityData {
            do {
                dailySteps = try await fetchDailySteps(from: startDate, to: endDate)
                let dailyActivity = try await fetchDailyActivity(from: startDate, to: endDate)
                totalActiveCalories = dailyActivity.reduce(0) { $0 + $1.activeCalories }
            } catch {
                debug(.service, "Failed to fetch activity data: \(error.localizedDescription)")
            }
        }

        // Fetch heart rate data if enabled
        if settings.enableHeartRateData {
            do {
                let restingReadings = try await fetchRestingHeartRate(from: startDate, to: endDate)
                if !restingReadings.isEmpty {
                    restingHR = restingReadings.last?.bpm
                }

                let hrReadings = try await fetchHeartRateReadings(from: startDate, to: endDate)
                if !hrReadings.isEmpty {
                    let bpms = hrReadings.map { $0.bpm }
                    avgHR = bpms.reduce(0, +) / bpms.count
                    minHR = bpms.min()
                    maxHR = bpms.max()
                }

                // Fetch HRV data
                let hrvReadings = try await fetchHRVReadings(from: startDate, to: endDate)
                if !hrvReadings.isEmpty {
                    // Group by day for summaries
                    var hrvByDay: [Date: [HRVReading]] = [:]
                    for reading in hrvReadings {
                        let day = Calendar.current.startOfDay(for: reading.date)
                        if hrvByDay[day] == nil {
                            hrvByDay[day] = []
                        }
                        hrvByDay[day]?.append(reading)
                    }

                    for (day, readings) in hrvByDay {
                        let sdnns = readings.map { $0.sdnn }
                        hrvSummaries.append(DailyHRVSummary(
                            date: day,
                            averageSDNN: sdnns.reduce(0, +) / Double(sdnns.count),
                            minSDNN: sdnns.min() ?? 0,
                            maxSDNN: sdnns.max() ?? 0,
                            readingCount: sdnns.count
                        ))
                    }
                    hrvSummaries.sort { $0.date < $1.date }

                    // Calculate average and trend
                    let allSDNN = hrvReadings.map { $0.sdnn }
                    avgHRV = allSDNN.reduce(0, +) / Double(allSDNN.count)

                    // Simple trend calculation (compare first half to second half)
                    if hrvSummaries.count >= 2 {
                        let midpoint = hrvSummaries.count / 2
                        let firstHalfAvg = hrvSummaries[..<midpoint].map { $0.averageSDNN }.reduce(0, +) / Double(midpoint)
                        let secondHalfAvg = hrvSummaries[midpoint...].map { $0.averageSDNN }.reduce(0, +) /
                            Double(hrvSummaries.count - midpoint)

                        let change = (secondHalfAvg - firstHalfAvg) / firstHalfAvg
                        if change > 0.1 {
                            hrvTrend = .increasing
                        } else if change < -0.1 {
                            hrvTrend = .decreasing
                        } else {
                            hrvTrend = .stable
                        }
                    }
                }
            } catch {
                debug(.service, "Failed to fetch heart rate data: \(error.localizedDescription)")
            }
        }

        // Fetch sleep data if enabled
        if settings.enableSleepData {
            do {
                sleepSummaries = try await fetchNightSleepSummaries(from: startDate, to: endDate)
            } catch {
                debug(.service, "Failed to fetch sleep data: \(error.localizedDescription)")
            }
        }

        // Fetch workout data if enabled
        if settings.enableWorkoutData {
            do {
                workouts = try await fetchWorkouts(from: startDate, to: endDate)
            } catch {
                debug(.service, "Failed to fetch workout data: \(error.localizedDescription)")
            }
        }

        // Calculate averages
        let averageSteps = dailySteps.isEmpty ? 0 : dailySteps.map { $0.count }.reduce(0, +) / dailySteps.count
        let avgSleepHours = sleepSummaries.isEmpty ? 0 : sleepSummaries.map { $0.hoursAsleep }.reduce(0, +) /
            Double(sleepSummaries.count)
        let avgSleepEfficiency = sleepSummaries.isEmpty ? nil : sleepSummaries.map { $0.sleepEfficiency }.reduce(0, +) /
            Double(sleepSummaries.count)
        let totalWorkoutMinutes = workouts.reduce(0) { $0 + $1.durationMinutes }

        // Group workouts by type
        var workoutsByType: [String: Int] = [:]
        for workout in workouts {
            workoutsByType[workout.workoutType, default: 0] += 1
        }

        return HealthMetricsExport(
            exportDate: Date(),
            startDate: startDate,
            endDate: endDate,
            dailySteps: dailySteps,
            averageSteps: averageSteps,
            totalActiveCalories: totalActiveCalories,
            restingHeartRate: restingHR,
            averageHeartRate: avgHR,
            minHeartRate: minHR,
            maxHeartRate: maxHR,
            hrvSummaries: hrvSummaries,
            averageHRV: avgHRV,
            hrvTrend: hrvTrend,
            sleepSummaries: sleepSummaries,
            averageSleepHours: avgSleepHours,
            averageSleepEfficiency: avgSleepEfficiency,
            workouts: workouts,
            totalWorkoutMinutes: totalWorkoutMinutes,
            workoutsByType: workoutsByType
        )
    }
}

// MARK: - Errors

enum HealthMetricsError: Error, LocalizedError {
    case typeNotAvailable
    case queryFailed(String)
    case noData

    var errorDescription: String? {
        switch self {
        case .typeNotAvailable:
            return "Health data type not available on this device"
        case .queryFailed(let message):
            return "Health query failed: \(message)"
        case .noData:
            return "No health data available for the requested period"
        }
    }
}
