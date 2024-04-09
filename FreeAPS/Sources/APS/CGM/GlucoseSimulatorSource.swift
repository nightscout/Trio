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
///  - IntelligentGenerator: BloodGlucoseGenerator

// TODO: Every itteration trend make two steps, but must only one

// TODO: Trend's value sticks to max and min Glucose value (in Glucose Generator)

// TODO: Add reaction to insulin

// TODO: Add probability to set trend's target value. Middle values must have more probability, than max and min.

import Combine
import Foundation
import LoopKitUI

// MARK: - Glucose simulator

final class GlucoseSimulatorSource: GlucoseSource {
    var cgmManager: CGMManagerUI?
    var glucoseManager: FetchGlucoseManager?

    private enum Config {
        // min time period to publish data
        static let workInterval: TimeInterval = 300
        // default BloodGlucose item at first run
        // 288 = 1 day * 24 hours * 60 minites * 60 seconds / workInterval
        static let defaultBGItems = 288
    }

    @Persisted(key: "GlucoseSimulatorLastGlucose") private var lastGlucose = 100

    @Persisted(key: "GlucoseSimulatorLastFetchDate") private var lastFetchDate: Date! = nil

    init() {
        if lastFetchDate == nil {
            var lastDate = Date()
            for _ in 1 ... Config.defaultBGItems {
                lastDate = lastDate.addingTimeInterval(-Config.workInterval)
            }
            lastFetchDate = lastDate
        }
    }

    private lazy var generator: BloodGlucoseGenerator = {
        IntelligentGenerator(
            currentGlucose: lastGlucose
        )
    }()

    private var canGenerateNewValues: Bool {
        guard let lastDate = lastFetchDate else { return true }
        if Calendar.current.dateComponents([.second], from: lastDate, to: Date()).second! >= Int(Config.workInterval) {
            return true
        } else {
            return false
        }
    }

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

    func fetchIfNeeded() -> AnyPublisher<[BloodGlucose], Never> {
        fetch(nil)
    }
}

// MARK: - Glucose generator

protocol BloodGlucoseGenerator {
    func getBloodGlucoses(startDate: Date, finishDate: Date, withInterval: TimeInterval) -> [BloodGlucose]
}

class IntelligentGenerator: BloodGlucoseGenerator {
    private enum Config {
        // max and min glucose of trend's target
        static let maxGlucose = 320
        static let minGlucose = 45
    }

    // target glucose of trend
    @Persisted(key: "GlucoseSimulatorTargetValue") private var trendTargetValue = 100
    // how many steps left in current trend
    @Persisted(key: "GlucoseSimulatorTargetSteps") private var trendStepsLeft = 1
    // direction of last step
    @Persisted(key: "GlucoseSimulatorDirection") private var trandsStepDirection = BloodGlucose.Direction.flat.rawValue
    var currentGlucose: Int
    let startup = Date()
    init(currentGlucose: Int) {
        self.currentGlucose = currentGlucose
    }

    func getBloodGlucoses(startDate: Date, finishDate: Date, withInterval interval: TimeInterval) -> [BloodGlucose] {
        var result = [BloodGlucose]()

        var _currentDate = startDate
        while _currentDate <= finishDate {
            result.append(getNextBloodGlucose(forDate: _currentDate))
            _currentDate = _currentDate.addingTimeInterval(interval)
        }

        return result
    }

    // get next glucose's value in current trend
    private func getNextBloodGlucose(forDate date: Date) -> BloodGlucose {
        let previousGlucose = currentGlucose
        makeStepInTrend()
        trandsStepDirection = getDirection(fromGlucose: previousGlucose, toGlucose: currentGlucose).rawValue
        let glucose = BloodGlucose(
            _id: UUID().uuidString,
            sgv: currentGlucose,
            direction: BloodGlucose.Direction(rawValue: trandsStepDirection),
            date: Decimal(Int(date.timeIntervalSince1970) * 1000),
            dateString: date,
            unfiltered: Decimal(currentGlucose),
            filtered: nil,
            noise: nil,
            glucose: currentGlucose,
            type: nil,
            activationDate: startup,
            sessionStartDate: startup,
            transmitterID: "SIMULATOR"
        )
        return glucose
    }

    private func setNewRandomTarget() {
        guard trendTargetValue > 0 else {
            trendTargetValue = Array(80 ... 110).randomElement()!
            return
        }
        let difference = (Array(-50 ... -20) + Array(20 ... 50)).randomElement()!
        let _value = trendTargetValue + difference
        if _value <= Config.minGlucose {
            trendTargetValue = Config.minGlucose
        } else if _value >= Config.maxGlucose {
            trendTargetValue = Config.maxGlucose
        } else {
            trendTargetValue = _value
        }
    }

    private func setNewRandomSteps() {
        trendStepsLeft = Array(3 ... 8).randomElement()!
    }

    private func getDirection(fromGlucose from: Int, toGlucose to: Int) -> BloodGlucose.Direction {
        BloodGlucose.Direction(trend: Int(to - from))
    }

    private func generateNewTrend() {
        setNewRandomTarget()
        setNewRandomSteps()
    }

    private func makeStepInTrend() {
        currentGlucose +=
            Int(Double((trendTargetValue - currentGlucose) / trendStepsLeft) * [0.3, 0.6, 1, 1.3, 1.6, 2.0].randomElement()!)
        trendStepsLeft -= 1
        if trendStepsLeft == 0 {
            generateNewTrend()
        }
    }

    func sourceInfo() -> [String: Any]? {
        [GlucoseSourceKey.description.rawValue: "Glucose simulator"]
    }
}
