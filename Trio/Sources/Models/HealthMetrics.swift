import Foundation
import HealthKit

// MARK: - Activity Models

struct DailySteps: JSON, Identifiable, Equatable {
    let id: UUID
    let date: Date
    let count: Int
    let source: String?

    init(id: UUID = UUID(), date: Date, count: Int, source: String? = nil) {
        self.id = id
        self.date = date
        self.count = count
        self.source = source
    }
}

struct DailyActivity: JSON, Identifiable, Equatable {
    let id: UUID
    let date: Date
    let steps: Int
    let activeCalories: Double
    let exerciseMinutes: Int

    init(id: UUID = UUID(), date: Date, steps: Int, activeCalories: Double, exerciseMinutes: Int) {
        self.id = id
        self.date = date
        self.steps = steps
        self.activeCalories = activeCalories
        self.exerciseMinutes = exerciseMinutes
    }
}

// MARK: - Heart Rate Models

struct HeartRateReading: JSON, Identifiable, Equatable {
    let id: UUID
    let date: Date
    let bpm: Int
    let context: HeartRateContext?
    let source: String?

    init(id: UUID = UUID(), date: Date, bpm: Int, context: HeartRateContext? = nil, source: String? = nil) {
        self.id = id
        self.date = date
        self.bpm = bpm
        self.context = context
        self.source = source
    }
}

enum HeartRateContext: String, JSON, CaseIterable {
    case resting
    case active
    case workout
    case sleep
}

struct HRVReading: JSON, Identifiable, Equatable {
    let id: UUID
    let date: Date
    let sdnn: Double // milliseconds
    let source: String?

    init(id: UUID = UUID(), date: Date, sdnn: Double, source: String? = nil) {
        self.id = id
        self.date = date
        self.sdnn = sdnn
        self.source = source
    }
}

struct DailyHRVSummary: JSON, Identifiable, Equatable {
    let id: UUID
    let date: Date
    let averageSDNN: Double
    let minSDNN: Double
    let maxSDNN: Double
    let readingCount: Int

    init(id: UUID = UUID(), date: Date, averageSDNN: Double, minSDNN: Double, maxSDNN: Double, readingCount: Int) {
        self.id = id
        self.date = date
        self.averageSDNN = averageSDNN
        self.minSDNN = minSDNN
        self.maxSDNN = maxSDNN
        self.readingCount = readingCount
    }
}

// MARK: - Sleep Models

struct SleepSession: JSON, Identifiable, Equatable {
    let id: UUID
    let start: Date
    let end: Date
    let stage: SleepStage
    let source: String?

    init(id: UUID = UUID(), start: Date, end: Date, stage: SleepStage, source: String? = nil) {
        self.id = id
        self.start = start
        self.end = end
        self.stage = stage
        self.source = source
    }

    var duration: TimeInterval {
        end.timeIntervalSince(start)
    }
}

enum SleepStage: Int, JSON, CaseIterable {
    case inBed = 0
    case asleepUnspecified = 1
    case awake = 2
    case asleepCore = 3
    case asleepDeep = 4
    case asleepREM = 5

    var displayName: String {
        switch self {
        case .inBed: return "In Bed"
        case .asleepUnspecified: return "Asleep"
        case .awake: return "Awake"
        case .asleepCore: return "Core Sleep"
        case .asleepDeep: return "Deep Sleep"
        case .asleepREM: return "REM Sleep"
        }
    }

    var isAsleep: Bool {
        switch self {
        case .asleepUnspecified, .asleepCore, .asleepDeep, .asleepREM:
            return true
        case .inBed, .awake:
            return false
        }
    }
}

struct NightSleepSummary: JSON, Identifiable, Equatable {
    let id: UUID
    let date: Date // Date of wake-up
    let bedtime: Date
    let wakeTime: Date
    let totalDuration: TimeInterval
    let timeAsleep: TimeInterval
    let timeAwake: TimeInterval
    let deepSleepDuration: TimeInterval?
    let remSleepDuration: TimeInterval?
    let coreSleepDuration: TimeInterval?

    init(
        id: UUID = UUID(),
        date: Date,
        bedtime: Date,
        wakeTime: Date,
        totalDuration: TimeInterval,
        timeAsleep: TimeInterval,
        timeAwake: TimeInterval,
        deepSleepDuration: TimeInterval? = nil,
        remSleepDuration: TimeInterval? = nil,
        coreSleepDuration: TimeInterval? = nil
    ) {
        self.id = id
        self.date = date
        self.bedtime = bedtime
        self.wakeTime = wakeTime
        self.totalDuration = totalDuration
        self.timeAsleep = timeAsleep
        self.timeAwake = timeAwake
        self.deepSleepDuration = deepSleepDuration
        self.remSleepDuration = remSleepDuration
        self.coreSleepDuration = coreSleepDuration
    }

    var hoursAsleep: Double {
        timeAsleep / 3600
    }

    var sleepEfficiency: Double {
        guard totalDuration > 0 else { return 0 }
        return timeAsleep / totalDuration
    }
}

// MARK: - Workout Models

struct WorkoutSession: JSON, Identifiable, Equatable {
    let id: UUID
    let workoutType: String
    let start: Date
    let end: Date
    let duration: TimeInterval
    let calories: Double?
    let distance: Double? // meters
    let averageHeartRate: Int?
    let source: String?

    init(
        id: UUID = UUID(),
        workoutType: String,
        start: Date,
        end: Date,
        duration: TimeInterval,
        calories: Double? = nil,
        distance: Double? = nil,
        averageHeartRate: Int? = nil,
        source: String? = nil
    ) {
        self.id = id
        self.workoutType = workoutType
        self.start = start
        self.end = end
        self.duration = duration
        self.calories = calories
        self.distance = distance
        self.averageHeartRate = averageHeartRate
        self.source = source
    }

    var durationMinutes: Int {
        Int(duration / 60)
    }
}

// MARK: - Aggregated Export Model

struct HealthMetricsExport: JSON, Equatable {
    let exportDate: Date
    let startDate: Date
    let endDate: Date

    // Activity
    let dailySteps: [DailySteps]
    let averageSteps: Int
    let totalActiveCalories: Double

    // Heart Rate
    let restingHeartRate: Int?
    let averageHeartRate: Int?
    let minHeartRate: Int?
    let maxHeartRate: Int?

    // HRV
    let hrvSummaries: [DailyHRVSummary]
    let averageHRV: Double?
    let hrvTrend: TrendDirection?

    // Sleep
    let sleepSummaries: [NightSleepSummary]
    let averageSleepHours: Double
    let averageSleepEfficiency: Double?

    // Workouts
    let workouts: [WorkoutSession]
    let totalWorkoutMinutes: Int
    let workoutsByType: [String: Int]

    init(
        exportDate: Date = Date(),
        startDate: Date,
        endDate: Date,
        dailySteps: [DailySteps] = [],
        averageSteps: Int = 0,
        totalActiveCalories: Double = 0,
        restingHeartRate: Int? = nil,
        averageHeartRate: Int? = nil,
        minHeartRate: Int? = nil,
        maxHeartRate: Int? = nil,
        hrvSummaries: [DailyHRVSummary] = [],
        averageHRV: Double? = nil,
        hrvTrend: TrendDirection? = nil,
        sleepSummaries: [NightSleepSummary] = [],
        averageSleepHours: Double = 0,
        averageSleepEfficiency: Double? = nil,
        workouts: [WorkoutSession] = [],
        totalWorkoutMinutes: Int = 0,
        workoutsByType: [String: Int] = [:]
    ) {
        self.exportDate = exportDate
        self.startDate = startDate
        self.endDate = endDate
        self.dailySteps = dailySteps
        self.averageSteps = averageSteps
        self.totalActiveCalories = totalActiveCalories
        self.restingHeartRate = restingHeartRate
        self.averageHeartRate = averageHeartRate
        self.minHeartRate = minHeartRate
        self.maxHeartRate = maxHeartRate
        self.hrvSummaries = hrvSummaries
        self.averageHRV = averageHRV
        self.hrvTrend = hrvTrend
        self.sleepSummaries = sleepSummaries
        self.averageSleepHours = averageSleepHours
        self.averageSleepEfficiency = averageSleepEfficiency
        self.workouts = workouts
        self.totalWorkoutMinutes = totalWorkoutMinutes
        self.workoutsByType = workoutsByType
    }

    var hasAnyData: Bool {
        !dailySteps.isEmpty || !hrvSummaries.isEmpty || !sleepSummaries.isEmpty || !workouts.isEmpty
    }
}

enum TrendDirection: String, JSON, CaseIterable {
    case increasing
    case decreasing
    case stable

    var displaySymbol: String {
        switch self {
        case .increasing: return "↑"
        case .decreasing: return "↓"
        case .stable: return "→"
        }
    }
}

// MARK: - Settings Model

struct HealthMetricsSettings: JSON, Equatable {
    var enableActivityData: Bool = false
    var enableSleepData: Bool = false
    var enableHeartRateData: Bool = false
    var enableWorkoutData: Bool = false

    var hasAnyEnabled: Bool {
        enableActivityData || enableSleepData || enableHeartRateData || enableWorkoutData
    }
}

extension HealthMetricsSettings {
    private enum CodingKeys: String, CodingKey {
        case enableActivityData
        case enableSleepData
        case enableHeartRateData
        case enableWorkoutData
    }
}

extension HealthMetricsSettings: Decodable {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        var settings = HealthMetricsSettings()

        if let enableActivityData = try? container.decode(Bool.self, forKey: .enableActivityData) {
            settings.enableActivityData = enableActivityData
        }

        if let enableSleepData = try? container.decode(Bool.self, forKey: .enableSleepData) {
            settings.enableSleepData = enableSleepData
        }

        if let enableHeartRateData = try? container.decode(Bool.self, forKey: .enableHeartRateData) {
            settings.enableHeartRateData = enableHeartRateData
        }

        if let enableWorkoutData = try? container.decode(Bool.self, forKey: .enableWorkoutData) {
            settings.enableWorkoutData = enableWorkoutData
        }

        self = settings
    }
}

// MARK: - HKWorkoutActivityType Extension

extension HKWorkoutActivityType {
    var displayName: String {
        switch self {
        case .americanFootball: return "American Football"
        case .archery: return "Archery"
        case .australianFootball: return "Australian Football"
        case .badminton: return "Badminton"
        case .baseball: return "Baseball"
        case .basketball: return "Basketball"
        case .bowling: return "Bowling"
        case .boxing: return "Boxing"
        case .climbing: return "Climbing"
        case .cricket: return "Cricket"
        case .crossTraining: return "Cross Training"
        case .curling: return "Curling"
        case .cycling: return "Cycling"
        case .dance: return "Dance"
        case .elliptical: return "Elliptical"
        case .equestrianSports: return "Equestrian Sports"
        case .fencing: return "Fencing"
        case .fishing: return "Fishing"
        case .functionalStrengthTraining: return "Strength Training"
        case .golf: return "Golf"
        case .gymnastics: return "Gymnastics"
        case .handball: return "Handball"
        case .hiking: return "Hiking"
        case .hockey: return "Hockey"
        case .hunting: return "Hunting"
        case .lacrosse: return "Lacrosse"
        case .martialArts: return "Martial Arts"
        case .mindAndBody: return "Mind and Body"
        case .paddleSports: return "Paddle Sports"
        case .play: return "Play"
        case .preparationAndRecovery: return "Recovery"
        case .racquetball: return "Racquetball"
        case .rowing: return "Rowing"
        case .rugby: return "Rugby"
        case .running: return "Running"
        case .sailing: return "Sailing"
        case .skatingSports: return "Skating"
        case .snowSports: return "Snow Sports"
        case .soccer: return "Soccer"
        case .softball: return "Softball"
        case .squash: return "Squash"
        case .stairClimbing: return "Stair Climbing"
        case .surfingSports: return "Surfing"
        case .swimming: return "Swimming"
        case .tableTennis: return "Table Tennis"
        case .tennis: return "Tennis"
        case .trackAndField: return "Track and Field"
        case .traditionalStrengthTraining: return "Weight Training"
        case .volleyball: return "Volleyball"
        case .walking: return "Walking"
        case .waterFitness: return "Water Fitness"
        case .waterPolo: return "Water Polo"
        case .waterSports: return "Water Sports"
        case .wrestling: return "Wrestling"
        case .yoga: return "Yoga"
        case .barre: return "Barre"
        case .coreTraining: return "Core Training"
        case .crossCountrySkiing: return "Cross Country Skiing"
        case .downhillSkiing: return "Downhill Skiing"
        case .flexibility: return "Flexibility"
        case .highIntensityIntervalTraining: return "HIIT"
        case .jumpRope: return "Jump Rope"
        case .kickboxing: return "Kickboxing"
        case .pilates: return "Pilates"
        case .snowboarding: return "Snowboarding"
        case .stairs: return "Stairs"
        case .stepTraining: return "Step Training"
        case .wheelchairWalkPace: return "Wheelchair Walk"
        case .wheelchairRunPace: return "Wheelchair Run"
        case .taiChi: return "Tai Chi"
        case .mixedCardio: return "Mixed Cardio"
        case .handCycling: return "Hand Cycling"
        case .discSports: return "Disc Sports"
        case .fitnessGaming: return "Fitness Gaming"
        case .cardioDance: return "Cardio Dance"
        case .socialDance: return "Social Dance"
        case .pickleball: return "Pickleball"
        case .cooldown: return "Cooldown"
        case .swimBikeRun: return "Triathlon"
        case .transition: return "Transition"
        @unknown default: return "Workout"
        }
    }
}
