import CoreData
import Foundation

extension OrefDetermination {
    static func fetch(_ predicate: NSPredicate = .predicateForOneDayAgo) -> NSFetchRequest<OrefDetermination> {
        let request = OrefDetermination.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \OrefDetermination.deliverAt, ascending: false)]
        request.predicate = predicate
        request.fetchLimit = 1
        return request
    }
}

extension Determination {
    var minPredBGFromReason: Decimal? {
        // Split reason into parts by semicolon and get first part
        let reasonParts = reason.components(separatedBy: "; ").first?.components(separatedBy: ", ") ?? []

        // Find the part that contains "minPredBG"
        if let minPredBGPart = reasonParts.first(where: { $0.contains("minPredBG") }) {
            // Extract the number after "minPredBG"
            let components = minPredBGPart.components(separatedBy: "minPredBG ")
            if let valueComponent = components.dropFirst().first {
                // Get everything after "minPredBG " and convert to Decimal
                let valueString = valueComponent.trimmingCharacters(in: CharacterSet(charactersIn: "0123456789.-").inverted)
                return Decimal(string: valueString)
            }
        }
        return nil
    }
}

extension OrefDetermination {
    var reasonParts: [String] {
        reason?.components(separatedBy: "; ").first?.components(separatedBy: ", ") ?? []
    }

    var reasonConclusion: String {
        reason?.components(separatedBy: "; ").last ?? ""
    }

    var minPredBGFromReason: Decimal? {
        // Find the part that contains "minPredBG"
        if let minPredBGPart = reasonParts.first(where: { $0.contains("minPredBG") }) {
            // Extract the number after "minPredBG"
            let components = minPredBGPart.components(separatedBy: "minPredBG ")
            if let valueComponent = components.dropFirst().first {
                // Get everything after "minPredBG " and convert to Decimal
                let valueString = valueComponent.trimmingCharacters(in: CharacterSet(charactersIn: "0123456789.-").inverted)
                return Decimal(string: valueString)
            }
        }
        return nil
    }
}

extension NSPredicate {
    static var enactedDetermination: NSPredicate {
        let date = Date.halfHourAgo
        return NSPredicate(format: "enacted == %@ AND timestamp >= %@", true as NSNumber, date as NSDate)
    }

    static var determinationsForCobIobCharts: NSPredicate {
        let date = Date.oneDayAgo
        return NSPredicate(format: "deliverAt >= %@", date as NSDate)
    }

    static var enactedDeterminationsNotYetUploadedToNightscout: NSPredicate {
        NSPredicate(
            format: "deliverAt >= %@ AND isUploadedToNS == %@ AND enacted == %@",
            Date.oneDayAgo as NSDate,
            false as NSNumber,
            true as NSNumber
        )
    }

    static var suggestedDeterminationsNotYetUploadedToNightscout: NSPredicate {
        NSPredicate(
            format: "deliverAt >= %@ AND isUploadedToNS == %@ AND (enacted == %@ OR enacted == nil OR enacted != %@)",
            Date.oneDayAgo as NSDate,
            false as NSNumber,
            true as NSNumber,
            true as NSNumber
        )
    }

    static var determinationsForStats: NSPredicate {
        let date = Date.threeMonthsAgo
        return NSPredicate(format: "deliverAt >= %@", date as NSDate)
    }
}

// MARK: - DeterminationDTO and Conformance to ImportableDTO

/// Data Transfer Object for the enacted.json.
struct DeterminationDTO: Decodable, ImportableDTO {
    let tdd: Decimal?
    let threshold: Decimal?
    let timestamp: String?
    let insulinForManualBolus: Decimal?
    let sensitivityRatio: Decimal?
    let predictions: Predictions?
    let received: Bool?
    let currentTarget: Decimal?
    let expectedDelta: Decimal?
    let cob: Int?
    let minDelta: Decimal?
    let bg: Decimal?
    let manualBolusErrorString: Decimal?
    let eventualBG: Decimal?
    let isf: Decimal?
    let rate: Decimal?
    let duration: Decimal?
    let temp: String?
    let insulinReq: Decimal?
    let insulin: Insulin?
    let deliverAt: String?
    let reason: String?
    let iob: Decimal?
    let reservoir: Decimal?

    enum CodingKeys: String, CodingKey {
        case tdd = "TDD"
        case threshold
        case timestamp
        case insulinForManualBolus
        case sensitivityRatio
        case predictions = "predBGs"
        case received = "recieved"
        case currentTarget = "current_target"
        case expectedDelta
        case cob = "COB"
        case minDelta
        case bg
        case manualBolusErrorString
        case eventualBG
        case isf = "ISF"
        case rate
        case duration
        case temp
        case insulinReq
        case insulin
        case deliverAt
        case reason
        case iob = "IOB"
        case reservoir
    }

    // Conformance to ImportableDTO
    typealias ManagedObject = OrefDetermination

    /// Stores the DTO in Core Data by mapping it to the corresponding managed object.
    func store(in context: NSManagedObjectContext) -> OrefDetermination {
        let determinationEntity = OrefDetermination(context: context)
        let dateFormatter = ISO8601DateFormatter()

        determinationEntity.timestamp = timestamp.flatMap { dateFormatter.date(from: $0) }
        determinationEntity.deliverAt = deliverAt.flatMap { dateFormatter.date(from: $0) }
        determinationEntity.cob = cob.map { Int16($0) } ?? 0
        determinationEntity.temp = temp
        determinationEntity.iob = iob.map { NSDecimalNumber(decimal: $0) }
        determinationEntity.minDelta = minDelta.map { NSDecimalNumber(decimal: $0) }
        determinationEntity.expectedDelta = expectedDelta.map { NSDecimalNumber(decimal: $0) }
        determinationEntity.rate = rate.map { NSDecimalNumber(decimal: $0) }
        determinationEntity.reason = reason
        determinationEntity.totalDailyDose = tdd.map { NSDecimalNumber(decimal: $0) }
        determinationEntity.reservoir = reservoir.map { NSDecimalNumber(decimal: $0) }
        determinationEntity.duration = duration.map { NSDecimalNumber(decimal: $0) }
        determinationEntity.currentTarget = currentTarget.map { NSDecimalNumber(decimal: $0) }
        determinationEntity.insulinForManualBolus = insulinForManualBolus.map { NSDecimalNumber(decimal: $0) }
        determinationEntity.sensitivityRatio = sensitivityRatio.map { NSDecimalNumber(decimal: $0) }
        determinationEntity.threshold = threshold.map { NSDecimalNumber(decimal: $0) }
        determinationEntity.eventualBG = eventualBG.map { NSDecimalNumber(decimal: $0) }
        determinationEntity.received = received ?? false
        determinationEntity.insulinReq = insulinReq.map { NSDecimalNumber(decimal: $0) }
        determinationEntity.insulinSensitivity = isf.map { NSDecimalNumber(decimal: $0) }
        determinationEntity.manualBolusErrorString = manualBolusErrorString.map { NSDecimalNumber(decimal: $0) }
        determinationEntity.glucose = bg.map { NSDecimalNumber(decimal: $0) }

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
