import Foundation
@testable import Trio

// Helper extension for Date from ISO string
extension Date {
    static func from(isoString: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime, .withTimeZone]
        return formatter.date(from: isoString)!
    }

    var iso8601String: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime, .withTimeZone]
        return formatter.string(from: self)
    }
}

extension CarbsEntry {
    static func forTest(createdAt: Date, carbs: Decimal) -> CarbsEntry {
        CarbsEntry(
            id: nil,
            createdAt: createdAt,
            actualDate: nil,
            carbs: carbs,
            fat: nil,
            protein: nil,
            note: nil,
            enteredBy: nil,
            isFPU: nil,
            fpuID: nil
        )
    }
}

extension TimeInterval {
    static func hours(_ hours: Double) -> TimeInterval {
        hours * 60 * 60
    }
}

extension [ComputedPumpHistoryEvent] {
    func netInsulin() -> Decimal { compactMap(\.insulin).reduce(0, +) }
}

extension Decimal {
    func isWithin(_ error: Decimal, of value: Decimal) -> Bool {
        (self - value).magnitude <= error
    }
}

extension Encodable {
    var prettyPrintedJSON: String? {
        let encoder = JSONCoding.encoder
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes, .sortedKeys]

        do {
            let data = try encoder.encode(self)
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }
}

extension IobResult {
    func approximatelyEquals(_ rhs: IobResult) -> Bool {
        // Compare all properties
        guard iob.isWithin(0.001, of: rhs.iob),
              activity.isWithin(0.0001, of: rhs.activity),
              basaliob.isWithin(0.001, of: rhs.basaliob),
              bolusiob.isWithin(0.001, of: rhs.bolusiob),
              netbasalinsulin.isWithin(0.05, of: rhs.netbasalinsulin),
              bolusinsulin.isWithin(0.001, of: rhs.bolusinsulin),
              time == rhs.time,
              lastBolusTime == rhs.lastBolusTime
        else {
            return false
        }

        // Compare nested IobWithZeroTemp
        guard iobWithZeroTemp.iob.isWithin(0.001, of: rhs.iobWithZeroTemp.iob),
              iobWithZeroTemp.activity.isWithin(0.0001, of: rhs.iobWithZeroTemp.activity),
              iobWithZeroTemp.basaliob.isWithin(0.001, of: rhs.iobWithZeroTemp.basaliob),
              iobWithZeroTemp.bolusiob.isWithin(0.001, of: rhs.iobWithZeroTemp.bolusiob),
              iobWithZeroTemp.netbasalinsulin.isWithin(0.05, of: rhs.iobWithZeroTemp.netbasalinsulin),
              iobWithZeroTemp.bolusinsulin.isWithin(0.001, of: rhs.iobWithZeroTemp.bolusinsulin),
              iobWithZeroTemp.time == rhs.iobWithZeroTemp.time
        else {
            return false
        }

        // Compare optional LastTemp
        if let selfTemp = lastTemp, let rhsTemp = rhs.lastTemp {
            guard let selfDuration = selfTemp.duration, let rhsDuration = rhsTemp.duration, selfDuration.isWithin(
                0.01,
                of: rhsDuration
            ) else {
                return false
            }
            // Both are non-nil, compare their properties
            return selfTemp.rate == rhsTemp.rate &&
                selfTemp.timestamp == rhsTemp.timestamp &&
                selfTemp.started_at == rhsTemp.started_at &&
                selfTemp.date == rhsTemp.date
        } else {
            // Both should be nil for equality
            return lastTemp == nil && rhs.lastTemp == nil
        }
    }
}

extension ComputedPumpHistoryEvent {
    func contains(tempBolus: ComputedPumpHistoryEvent) -> Bool {
        guard type == .tempBasal, tempBolus.isTempBolus else {
            fatalError("invalid type for computed pump history event")
        }

        let start = timestamp
        let end = start + duration!.minutesToSeconds

        return start <= tempBolus.timestamp && end > tempBolus.timestamp
    }
}
