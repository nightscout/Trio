import CoreData
import Foundation

struct Determination: JSON, Equatable, Decodable {
    let id: UUID?
    var reason: String
    let units: Decimal?
    let insulinReq: Decimal?
    var eventualBG: Int?
    let sensitivityRatio: Decimal?
    let rate: Decimal?
    let duration: Decimal?
    let iob: Decimal?
    let cob: Decimal?
    var predictions: Predictions?
    var deliverAt: Date?
    let carbsReq: Decimal?
    let temp: TempType?
    var bg: Decimal?
    let reservoir: Decimal?
    var isf: Decimal?
    var timestamp: Date?
    let tdd: Decimal?
    let insulin: Insulin?
    var current_target: Decimal?
    let insulinForManualBolus: Decimal?
    let manualBolusErrorString: Decimal?
    var minDelta: Decimal?
    var expectedDelta: Decimal?
    var minGuardBG: Decimal?
    var minPredBG: Decimal?
    var threshold: Decimal?
    let carbRatio: Decimal?
    let received: Bool?
}

struct Determination2: Decodable, ImportableDTO {
    var timestamp: String? // JSON outputs `timestamp` as String
    var deliverAt: String?
    var cob: Int
    var temp: String?
    var iob: Double? // JSON outputs IOB as Double
    var minDelta: Double?
    var expectedDelta: Double?
    var rate: Double?
    var reason: String?
    var tdd: Double?
    var reservoir: Int? // JSON outputs reservoir as Int
    var duration: Int
    var currentTarget: Double?
    var insulinForManualBolus: Double?
    var sensitivityRatio: Double?
    var threshold: Double?
    var eventualBG: Double?
    var predictions: Predictions?
    var received: Bool // typo
    var minGuardBG: Double?
    var insulin: Insulin?
    var insulinReq: Double?
    var isf: Double?
    var manualBolusErrorString: Double?
    var cr: Double?
    var bg: Double?

    enum CodingKeys: String, CodingKey {
        case timestamp
        case deliverAt
        case cob = "COB"
        case temp
        case iob = "IOB"
        case minDelta
        case expectedDelta
        case rate
        case reason
        case tdd = "TDD"
        case reservoir
        case duration
        case currentTarget = "current_target"
        case insulinForManualBolus
        case sensitivityRatio
        case threshold
        case eventualBG
        case predictions = "predBGs"
        case received = "recieved" // typo corrected
        case minGuardBG
        case insulin
        case insulinReq
        case isf = "ISF"
        case manualBolusErrorString
        case cr = "CR"
        case bg
    }

    struct Predictions: Decodable {
        var iob: [Int]?
        var zt: [Int]?
        var uam: [Int]?

        enum CodingKeys: String, CodingKey {
            case iob = "IOB"
            case zt = "ZT"
            case uam = "UAM"
        }
    }

    struct Insulin: Decodable {
        var tempBasal: Decimal?
        var bolus: Decimal?
        var tdd: Decimal?
        var scheduledBasal: Decimal?

        enum CodingKeys: String, CodingKey {
            case tempBasal = "temp_basal"
            case bolus
            case tdd = "TDD"
            case scheduledBasal = "scheduled_basal"
        }
    }

    typealias ManagedObject = OrefDetermination

    func store(in context: NSManagedObjectContext) -> OrefDetermination {
        let determinationEntity = OrefDetermination(context: context)

        determinationEntity.timestamp = convertToDate(from: timestamp)
        determinationEntity.deliverAt = convertToDate(from: deliverAt)
        determinationEntity.cob = Int16(cob)
        determinationEntity.temp = temp
        determinationEntity.iob = convertToDecimalNumber(from: iob)
        determinationEntity.minDelta = convertToDecimalNumber(from: minDelta)
        determinationEntity.expectedDelta = convertToDecimalNumber(from: expectedDelta)
        determinationEntity.rate = convertToDecimalNumber(from: rate)
        determinationEntity.reason = reason
        determinationEntity.totalDailyDose = convertToDecimalNumber(from: tdd)
        determinationEntity.reservoir = convertToDecimalNumber(from: reservoir)
        determinationEntity.duration = NSDecimalNumber(value: duration)
        determinationEntity.currentTarget = convertToDecimalNumber(from: currentTarget)
        determinationEntity.insulinForManualBolus = convertToDecimalNumber(from: insulinForManualBolus)
        determinationEntity.sensitivityRatio = convertToDecimalNumber(from: sensitivityRatio)
        determinationEntity.threshold = convertToDecimalNumber(from: threshold)
        determinationEntity.eventualBG = convertToDecimalNumber(from: eventualBG)
        determinationEntity.received = received
        determinationEntity.insulinReq = convertToDecimalNumber(from: insulinReq)
        determinationEntity.insulinSensitivity = convertToDecimalNumber(from: isf)
        determinationEntity.manualBolusErrorString = convertToDecimalNumber(from: manualBolusErrorString)
        determinationEntity.carbRatio = convertToDecimalNumber(from: cr)
        determinationEntity.glucose = convertToDecimalNumber(from: bg)

        if let predictionData = predictions {
            var forecasts = Set<Forecast>()

            if let iobPredictions = predictionData.iob {
                forecasts.insert(createForecast(context: context, type: "IOB", values: iobPredictions))
            }
            if let ztPredictions = predictionData.zt {
                forecasts.insert(createForecast(context: context, type: "ZT", values: ztPredictions))
            }
            if let uamPredictions = predictionData.uam {
                forecasts.insert(createForecast(context: context, type: "UAM", values: uamPredictions))
            }

            determinationEntity.forecasts = forecasts
        }

        return determinationEntity
    }

    private func convertToDecimalNumber(from value: Double?) -> NSDecimalNumber? {
        guard let value = value else { return nil }
        return NSDecimalNumber(value: value)
    }

    private func convertToDecimalNumber(from value: Int?) -> NSDecimalNumber? {
        guard let value = value else { return nil }
        return NSDecimalNumber(value: value)
    }

    private func convertToDate(from string: String?) -> Date? {
        guard let string = string else { return nil }
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: string)
    }

    private func createForecast(context: NSManagedObjectContext, type: String, values: [Int]) -> Forecast {
        let forecast = Forecast(context: context)
        forecast.type = type
        forecast.date = Date()
        forecast.forecastValues = Set(values.enumerated().map { index, value in
            let forecastValue = ForecastValue(context: context)
            forecastValue.index = Int32(index)
            forecastValue.value = Int32(value)
            return forecastValue
        })
        return forecast
    }
}

struct Predictions: JSON, Equatable {
    let iob: [Int]?
    let zt: [Int]?
    let cob: [Int]?
    let uam: [Int]?
}

struct Insulin: JSON, Equatable {
    let TDD: Decimal?
    let bolus: Decimal?
    let temp_basal: Decimal?
    let scheduled_basal: Decimal?
}

extension Determination {
    private enum CodingKeys: String, CodingKey {
        case id
        case reason
        case units
        case insulinReq
        case eventualBG
        case sensitivityRatio
        case rate
        case duration
        case iob = "IOB"
        case cob = "COB"
        case predictions = "predBGs"
        case deliverAt
        case carbsReq
        case temp
        case bg
        case reservoir
        case timestamp
        case isf = "ISF"
        case tdd = "TDD"
        case insulin
        case current_target
        case insulinForManualBolus
        case manualBolusErrorString
        case minDelta
        case expectedDelta
        case minGuardBG
        case minPredBG
        case threshold
        case carbRatio = "CR"
        case received
    }
}

extension Predictions {
    private enum CodingKeys: String, CodingKey {
        case iob = "IOB"
        case zt = "ZT"
        case cob = "COB"
        case uam = "UAM"
    }
}

extension Insulin {
    private enum CodingKeys: String, CodingKey {
        case TDD
        case bolus
        case temp_basal
        case scheduled_basal
    }
}

protocol DeterminationObserver {
    func determinationDidUpdate(_ determination: Determination)
}

extension Determination {
    var reasonParts: [String] {
        reason.components(separatedBy: "; ").first?.components(separatedBy: ", ") ?? []
    }

    var reasonConclusion: String {
        reason.components(separatedBy: "; ").last ?? ""
    }
}
