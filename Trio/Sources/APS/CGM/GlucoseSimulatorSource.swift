/// Glucose source - Blood Glucose Simulator
///
/// Source publish fake data about glucose's level, creates ascending and descending trends
///
/// Enter point of Source is GlucoseSimulatorSource.fetch method. Method is called from FetchGlucoseManager module.
/// Not more often than a specified period (default - 300 seconds), it returns a Combine-publisher that publishes data on glucose values (global type BloodGlucose). If there is no up-to-date data (or the publication period has not passed yet), then a publisher of type Empty is returned, otherwise it returns a publisher of type Just.
///
/// Simulator composition
/// ===================
///
/// class GlucoseSimulatorSource - main class
/// protocol BloodGlucoseGenerator
///  - OscillatingGenerator: BloodGlucoseGenerator - Generates sinusoidal glucose values around a center point

import Combine
import Foundation
import LoopKitUI

// MARK: - Glucose simulator

/// A class that simulates glucose values for testing purposes.
/// This class implements the GlucoseSource protocol and provides simulated glucose readings
/// using different generator strategies.
final class GlucoseSimulatorSource: GlucoseSource {
    var cgmManager: CGMManagerUI?
    var glucoseManager: FetchGlucoseManager?

    private enum Config {
        /// Minimum time period between data publications (in seconds)
        static let workInterval: TimeInterval = 300
        /// Default number of blood glucose items to generate at first run
        /// 288 = 1 day * 24 hours * 60 minutes * 60 seconds / workInterval
        static let defaultBGItems = 288
    }

    /// The last glucose value that was generated
    @Persisted(key: "GlucoseSimulatorLastGlucose") private var lastGlucose = 100

    /// The date of the last fetch operation
    @Persisted(key: "GlucoseSimulatorLastFetchDate") private var lastFetchDate: Date! = nil

    /// Initializes the glucose simulator source
    /// Sets up the initial fetch date if not already set
    init() {
        if lastFetchDate == nil {
            var lastDate = Date()
            for _ in 1 ... Config.defaultBGItems {
                lastDate = lastDate.addingTimeInterval(-Config.workInterval)
            }
            lastFetchDate = lastDate
        }
    }

    /// The glucose generator used to create simulated values
    /// Uses OscillatingGenerator to create a sinusoidal pattern around 120 mg/dL
    private lazy var generator: BloodGlucoseGenerator = {
        OscillatingGenerator()
    }()

    /// Determines if new glucose values can be generated based on the time elapsed since the last fetch
    private var canGenerateNewValues: Bool {
        guard let lastDate = lastFetchDate else { return true }
        if Calendar.current.dateComponents([.second], from: lastDate, to: Date()).second! >= Int(Config.workInterval) {
            return true
        } else {
            return false
        }
    }

    /// Fetches new glucose values if enough time has passed since the last fetch
    /// - Parameter timer: Optional dispatch timer (not used in this implementation)
    /// - Returns: A publisher that emits an array of BloodGlucose objects
    func fetch(_: DispatchTimer?) -> AnyPublisher<[BloodGlucose], Never> {
        guard canGenerateNewValues else {
            return Just([]).eraseToAnyPublisher()
        }

        let glucoses = generator.getBloodGlucoses(
            startDate: lastFetchDate,
            finishDate: Date(),
            withInterval: Config.workInterval
        )

        if let lastItem = glucoses.last {
            lastGlucose = lastItem.glucose!
            lastFetchDate = Date()
        }

        return Just(glucoses).eraseToAnyPublisher()
    }

    /// Fetches new glucose values if needed
    /// - Returns: A publisher that emits an array of BloodGlucose objects
    func fetchIfNeeded() -> AnyPublisher<[BloodGlucose], Never> {
        fetch(nil)
    }
}

// MARK: - Glucose generator

/// Protocol defining the interface for glucose generators
/// Implementations of this protocol provide different strategies for generating glucose values
protocol BloodGlucoseGenerator {
    /// Generates blood glucose values between the specified dates at the given interval
    /// - Parameters:
    ///   - startDate: The start date for generating values
    ///   - finishDate: The end date for generating values
    ///   - interval: The time interval between generated values
    /// - Returns: An array of BloodGlucose objects
    func getBloodGlucoses(startDate: Date, finishDate: Date, withInterval: TimeInterval) -> [BloodGlucose]
}

/// A glucose generator that creates a sinusoidal pattern around a center value
/// This generator simulates a realistic oscillating glucose pattern with configurable parameters
class OscillatingGenerator: BloodGlucoseGenerator {
    /// Default values for simulator parameters
    enum Defaults {
        static let centerValue: Double = 120.0
        static let amplitude: Double = 45.0
        static let period: Double = 10800.0 // 3 hours in seconds
        static let noiseAmplitude: Double = 5.0
        static let produceStaleValues: Bool = false
    }

    /// UserDefaults keys for storing simulator parameters
    private enum UserDefaultsKeys {
        static let centerValue = "GlucoseSimulator_CenterValue"
        static let amplitude = "GlucoseSimulator_Amplitude"
        static let period = "GlucoseSimulator_Period"
        static let noiseAmplitude = "GlucoseSimulator_NoiseAmplitude"
        static let produceStaleValues = "GlucoseSimulator_ProduceStaleValues"
    }

    /// Amplitude of the oscillation (±45 mg/dL to create range from ~80 to ~170)
    private var amplitude: Double {
        get { UserDefaults.standard.double(forKey: UserDefaultsKeys.amplitude) != 0 ?
            UserDefaults.standard.double(forKey: UserDefaultsKeys.amplitude) :
            Defaults.amplitude }
        set { UserDefaults.standard.set(newValue, forKey: UserDefaultsKeys.amplitude) }
    }

    /// Period of the oscillation in seconds (3 hours = 10800 seconds)
    private var period: Double {
        get { UserDefaults.standard.double(forKey: UserDefaultsKeys.period) != 0 ?
            UserDefaults.standard.double(forKey: UserDefaultsKeys.period) :
            Defaults.period }
        set { UserDefaults.standard.set(newValue, forKey: UserDefaultsKeys.period) }
    }

    /// Center value of the oscillation (target glucose level)
    private var centerValue: Double {
        get { UserDefaults.standard.double(forKey: UserDefaultsKeys.centerValue) != 0 ?
            UserDefaults.standard.double(forKey: UserDefaultsKeys.centerValue) :
            Defaults.centerValue }
        set { UserDefaults.standard.set(newValue, forKey: UserDefaultsKeys.centerValue) }
    }

    /// Amplitude of random noise to add to the values (±5 mg/dL)
    private var noiseAmplitude: Double {
        get { UserDefaults.standard.double(forKey: UserDefaultsKeys.noiseAmplitude) != 0 ?
            UserDefaults.standard.double(forKey: UserDefaultsKeys.noiseAmplitude) :
            Defaults.noiseAmplitude }
        set { UserDefaults.standard.set(newValue, forKey: UserDefaultsKeys.noiseAmplitude) }
    }

    /// Whether to produce stale (unchanging) glucose values
    var produceStaleValues: Bool {
        get { UserDefaults.standard.bool(forKey: UserDefaultsKeys.produceStaleValues) }
        set { UserDefaults.standard.set(newValue, forKey: UserDefaultsKeys.produceStaleValues) }
    }

    /// Start date for the simulation
    private let startup = Date()

    /// Last generated glucose value for stale mode
    private var lastGeneratedGlucose: Int?

    /// Provides information string to describe the simulator as glucose source
    func sourceInfo() -> [String: Any]? {
        [GlucoseSourceKey.description.rawValue: "Glucose simulator"]
    }

    /// Reset all parameters to default values
    func resetToDefaults() {
        centerValue = Defaults.centerValue
        amplitude = Defaults.amplitude
        period = Defaults.period
        noiseAmplitude = Defaults.noiseAmplitude
        produceStaleValues = Defaults.produceStaleValues
        lastGeneratedGlucose = nil
    }

    /// Generates blood glucose values between the specified dates at the given interval
    /// - Parameters:
    ///   - startDate: The start date for generating values
    ///   - finishDate: The end date for generating values
    ///   - interval: The time interval between generated values
    /// - Returns: An array of BloodGlucose objects with sinusoidal pattern
    func getBloodGlucoses(startDate: Date, finishDate: Date, withInterval interval: TimeInterval) -> [BloodGlucose] {
        var result = [BloodGlucose]()
        var currentDate = startDate

        while currentDate <= finishDate {
            let glucose: Int
            let direction: BloodGlucose.Direction

            if produceStaleValues, lastGeneratedGlucose != nil {
                // In stale mode, use the last generated glucose value
                glucose = lastGeneratedGlucose!
                direction = .flat
            } else {
                // Generate a new glucose value
                glucose = generate(date: currentDate)
                direction = calculateDirection(at: currentDate)
                lastGeneratedGlucose = glucose
            }

            // Create BloodGlucose with the correct constructor
            let bloodGlucose = BloodGlucose(
                _id: UUID().uuidString,
                sgv: glucose,
                direction: direction,
                date: Decimal(Int(currentDate.timeIntervalSince1970) * 1000),
                dateString: currentDate,
                unfiltered: Decimal(glucose),
                filtered: nil,
                noise: nil,
                glucose: glucose,
                type: nil,
                activationDate: startup,
                sessionStartDate: startup,
                transmitterID: "SIMULATOR"
            )

            result.append(bloodGlucose)
            currentDate = currentDate.addingTimeInterval(interval)
        }

        return result
    }

    /// Generates a glucose value for the specified date using a sinusoidal function
    /// - Parameter date: The date for which to generate the glucose value
    /// - Returns: An integer representing the glucose value in mg/dL
    private func generate(date: Date) -> Int {
        // Time in seconds since 1970
        let timeSeconds = date.timeIntervalSince1970

        // Calculate sine value
        let sinValue = sin(2.0 * .pi * timeSeconds / period)

        // Random noise
        let noise = Double.random(in: -noiseAmplitude ... noiseAmplitude)

        // Calculate glucose value: center + amplitude * sine + noise
        let glucoseValue = centerValue + amplitude * sinValue + noise

        // Return as integer
        return Int(glucoseValue)
    }

    /// Calculates the direction (trend) of glucose change at the specified date
    /// - Parameter date: The date for which to calculate the direction
    /// - Returns: A BloodGlucose.Direction value indicating the trend
    private func calculateDirection(at date: Date) -> BloodGlucose.Direction {
        // Time in seconds since 1970
        let timeSeconds = date.timeIntervalSince1970

        // Calculate derivative of sine function (cosine)
        let cosValue = cos(2.0 * .pi * timeSeconds / period)

        // Slope of the curve at this point
        let slope = -amplitude * 2.0 * .pi / period * cosValue

        // Determine direction based on slope
        if abs(slope) < 0.2 {
            return .flat
        } else if slope > 0 {
            if slope > 1.0 {
                return .singleUp
            } else {
                return .fortyFiveUp
            }
        } else {
            if slope < -1.0 {
                return .singleDown
            } else {
                return .fortyFiveDown
            }
        }
    }
}
