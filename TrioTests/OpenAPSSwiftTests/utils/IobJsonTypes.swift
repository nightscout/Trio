import Foundation
@testable import Trio

protocol BaseHistoryRecord {
    var date: UInt64 { get }
}

// For insulin bolus records
struct InsulinRecord: BaseHistoryRecord, Codable {
    let insulin: Decimal
    let date: UInt64
    let created_at: Date?
    let started_at: Date?
    let timestamp: Date?

    enum CodingKeys: String, CodingKey {
        case insulin
        case date
        case created_at
        case started_at
        case timestamp
    }

    func mismatch(field: String, record: ComputedPumpHistoryEvent) -> Bool {
        print("Insulin mismatch \(field) json date: \(date) swift: \(record.date)")
        return false
    }

    func matches(record: ComputedPumpHistoryEvent) -> Bool {
        if insulin != record.insulin {
            return mismatch(field: "insulin", record: record)
        }

        if date != record.date, (date - 1) != record.date {
            return mismatch(field: "date", record: record)
        }

        if let timestamp = timestamp, timestamp != record.timestamp {
            return mismatch(field: "timestamp", record: record)
        }

        if let started_at = started_at, started_at != record.started_at {
            return mismatch(field: "started_at", record: record)
        }

        return true
    }
}

// For temporary basal rate records
struct BasalRateRecord: BaseHistoryRecord, Codable {
    let rate: Decimal
    let timestamp: Date?
    let started_at: Date?
    let date: UInt64
    let duration: Decimal

    enum CodingKeys: String, CodingKey {
        case rate
        case timestamp
        case started_at
        case date
        case duration
    }

    func mismatch(field: String, record: ComputedPumpHistoryEvent) -> Bool {
        print("Basal mismatch \(field) json date: \(date) swift: \(record.date)")
        return false
    }

    func matches(record: ComputedPumpHistoryEvent) -> Bool {
        if rate != record.rate! {
            return mismatch(field: "rate", record: record)
        }

        if date != record.date {
            return mismatch(field: "date", record: record)
        }

        if !duration.isWithin(0.00001, of: record.duration!) {
            return mismatch(field: "duration", record: record)
        }

        if let timestamp = timestamp, timestamp != record.timestamp {
            return mismatch(field: "timestamp", record: record)
        }

        if let started_at = started_at, started_at != record.started_at {
            return mismatch(field: "started_at", record: record)
        }

        return true
    }
}

// Helper enum to handle either type of record
enum HistoryRecord: Decodable {
    case insulin(InsulinRecord)
    case basal(BasalRateRecord)

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let date: UInt64
        if let doubleDate = try? container.decode(Double.self, forKey: .date) {
            date = UInt64(doubleDate)
        } else {
            date = try container.decode(UInt64.self, forKey: .date)
        }

        // If not basal, it must be insulin - check for insulin value
        if let insulin = try? container.decode(Decimal.self, forKey: .insulin) {
            // Handle both formats of insulin records
            let created_at = try? container.decode(Date.self, forKey: .created_at)
            let timestamp = try? container.decode(Date.self, forKey: .timestamp)
            let started_at = try? container.decode(Date.self, forKey: .started_at)

            self = .insulin(InsulinRecord(
                insulin: insulin,
                date: date,
                created_at: created_at,
                started_at: started_at,
                timestamp: timestamp
            ))
            return
        }

        // Otherwise, try to decode as basal record
        let rate = try container.decode(Decimal.self, forKey: .rate)
        let timestamp = try? container.decode(Date.self, forKey: .timestamp)
        let started_at = try? container.decode(Date.self, forKey: .started_at)
        let duration = try container.decode(Decimal.self, forKey: .duration)

        self = .basal(BasalRateRecord(
            rate: rate,
            timestamp: timestamp,
            started_at: started_at,
            date: date,
            duration: duration
        ))
    }

    func matches(_ event: ComputedPumpHistoryEvent) -> Bool {
        switch self {
        case let .insulin(record):
            return record.matches(record: event)

        case let .basal(record):
            return record.matches(record: event)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case insulin
        case date
        case created_at
        case rate
        case timestamp
        case started_at
        case duration
    }
}
