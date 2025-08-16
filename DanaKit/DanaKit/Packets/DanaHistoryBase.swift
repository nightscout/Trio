enum HistoryCode {
    static let RECORD_TYPE_DONE_UPLOAD = -0x01
    static let RECORD_TYPE_UNKNOWN = 0x00
    static let RECORD_TYPE_BOLUS = 0x02
    static let RECORD_TYPE_DAILY = 0x03
    static let RECORD_TYPE_PRIME = 0x04
    static let RECORD_TYPE_REFILL = 0x05
    static let RECORD_TYPE_GLUCOSE = 0x06
    static let RECORD_TYPE_CARBO = 0x07
    static let RECORD_TYPE_SUSPEND = 0x09
    static let RECORD_TYPE_ALARM = 0x0A
    static let RECORD_TYPE_BASALHOUR = 0x0B
    static let RECORD_TYPE_TEMP_BASAL = 0x99
}

struct PacketHistoryBase {
    var from: Date?
    var usingUtc: Bool
}

struct HistoryItem {
    var code: Int
    var raw: Data
    var timestamp: Date
    var value: Double?
    var durationInMin: Double?
    var dailyBasal: Double?
    var dailyBolus: Double?
    var alarm: UInt8?
    var bolusType: String?
}

func generatePacketHistoryData(options: PacketHistoryBase) -> Data {
    var data = Data(count: 6)

    if options.from == nil {
        data[0] = 0
        data[1] = 1
        data[2] = 1
        data[3] = 0
        data[4] = 0
        data[5] = 0
    } else {
        data.addDate(at: 0, date: options.from!, utc: options.usingUtc)
    }

    return data
}

func parsePacketHistory(data: Data, usingUtc: Bool?) -> DanaParsePacket<HistoryItem> {
    let usingUtc = usingUtc ?? true
    if data.count == 3 {
        return DanaParsePacket(
            success: false,
            rawData: data,
            data: HistoryItem(
                code: HistoryCode.RECORD_TYPE_UNKNOWN,
                raw: data,
                timestamp: Date(),
                value: Double(data[DataStart])
            )
        )
    }

    // This packet marks the upload of history to be done
    if data.count == 5 {
        return DanaParsePacket(
            success: data[DataStart] == 0x00,
            rawData: data,
            data: HistoryItem(
                code: HistoryCode.RECORD_TYPE_DONE_UPLOAD,
                raw: data,
                timestamp: Date(),
                value: Double(data[DataStart])
            )
        )
    }

    let param7 = data[DataStart + 6]
    let param8 = data[DataStart + 7]
    let value = (UInt16(data[DataStart + 8]) << 8) + UInt16(data[DataStart + 9])

    let recordType = Int(data[DataStart])
    switch recordType {
    case HistoryCode.RECORD_TYPE_BOLUS:
        return DanaParsePacket(
            success: true,
            rawData: data,
            data: HistoryItem(
                code: HistoryCode.RECORD_TYPE_BOLUS,
                raw: data,
                timestamp: data.date(at: DataStart + 1, usingUtc),
                value: Double(value) * 0.01,
                durationInMin: Double((param8 & 0x0F) * 60 + param7),
                bolusType: getBolusType(param8: param8)
            )
        )

    case HistoryCode.RECORD_TYPE_DAILY:
        let dailyBasal = Double((UInt16(data[DataStart + 4]) << 8) + UInt16(data[DataStart + 5])) * 0.01
        let dailyBolus = Double((UInt16(data[DataStart + 6]) << 8) + UInt16(data[DataStart + 7])) * 0.01
        var timestamp = data.date(at: DataStart + 1, usingUtc)
        timestamp = Calendar.current.date(bySettingHour: 0, minute: 0, second: 0, of: timestamp) ?? timestamp

        return DanaParsePacket(
            success: true,
            rawData: data,
            data: HistoryItem(
                code: HistoryCode.RECORD_TYPE_DAILY,
                raw: data,
                timestamp: timestamp,
                dailyBasal: dailyBasal,
                dailyBolus: dailyBolus
            )
        )

    case HistoryCode.RECORD_TYPE_PRIME:
        return DanaParsePacket(
            success: true,
            rawData: data,
            data: HistoryItem(
                code: HistoryCode.RECORD_TYPE_PRIME,
                raw: data,
                timestamp: data.date(at: DataStart + 1, usingUtc),
                value: Double(value) * 0.01
            )
        )

    case HistoryCode.RECORD_TYPE_REFILL:
        return DanaParsePacket(
            success: true,
            rawData: data,
            data: HistoryItem(
                code: HistoryCode.RECORD_TYPE_REFILL,
                raw: data,
                timestamp: data.date(at: DataStart + 1, usingUtc),
                value: Double(value) * 0.01
            )
        )

    case HistoryCode.RECORD_TYPE_BASALHOUR:
        return DanaParsePacket(
            success: true,
            rawData: data,
            data: HistoryItem(
                code: HistoryCode.RECORD_TYPE_BASALHOUR,
                raw: data,
                timestamp: data.date(at: DataStart + 1, usingUtc),
                value: Double(value) * 0.01
            )
        )

    case HistoryCode.RECORD_TYPE_TEMP_BASAL:
        return DanaParsePacket(
            success: true,
            rawData: data,
            data: HistoryItem(
                code: HistoryCode.RECORD_TYPE_TEMP_BASAL,
                raw: data,
                timestamp: data.date(at: DataStart + 1, usingUtc),
                value: Double(value) * 0.01
            )
        )

    case HistoryCode.RECORD_TYPE_GLUCOSE:
        return DanaParsePacket(
            success: true,
            rawData: data,
            data: HistoryItem(
                code: HistoryCode.RECORD_TYPE_GLUCOSE,
                raw: data,
                timestamp: data.date(at: DataStart + 1, usingUtc),
                value: Double(value)
            )
        )

    case HistoryCode.RECORD_TYPE_CARBO:
        return DanaParsePacket(
            success: true,
            rawData: data,
            data: HistoryItem(
                code: HistoryCode.RECORD_TYPE_CARBO,
                raw: data,
                timestamp: data.date(at: DataStart + 1, usingUtc),
                value: Double(value)
            )
        )

    case HistoryCode.RECORD_TYPE_SUSPEND:
        return DanaParsePacket(
            success: true,
            rawData: data,
            data: HistoryItem(
                code: HistoryCode.RECORD_TYPE_SUSPEND,
                raw: data,
                timestamp: data.date(at: DataStart + 1, usingUtc),
                value: param8 == 0x4F ? 1 : 0
            )
        )

    case HistoryCode.RECORD_TYPE_ALARM:
        return DanaParsePacket(
            success: true,
            rawData: data,
            data: HistoryItem(
                code: HistoryCode.RECORD_TYPE_ALARM,
                raw: data,
                timestamp: data.date(at: DataStart + 1, usingUtc),
                value: Double(value) * 0.01,
                alarm: param8 // getAlarmMessage(param8: param8)
            )
        )

    default:
        return DanaParsePacket(
            success: false,
            rawData: data,
            data: HistoryItem(
                code: HistoryCode.RECORD_TYPE_UNKNOWN,
                raw: data,
                timestamp: data.date(at: DataStart + 1, usingUtc),
                alarm: UInt8(recordType) // "UNKNOWN Message type: \(recordType)"
            )
        )
    }
}

func getBolusType(param8: UInt8) -> String {
    switch param8 & 0xF0 {
    case 0xA0:
        return "DS"
    case 0xC0:
        return "E"
    case 0x80:
        return "S"
    case 0x90:
        return "DE"
    default:
        return "None"
    }
}

func getAlarmMessage(param8: UInt8?) -> String {
    guard let param8 = param8 else {
        return ""
    }

    switch param8 {
    case 0x50:
        return "Basal Compare"
    case 0x52:
        return "Empty Reservoir"
    case 0x43:
        return "Check"
    case 0x4F:
        return "Occlusion"
    case 0x4D:
        return "Basal max"
    case 0x44:
        return "Daily max"
    case 0x42:
        return "Low Battery"
    case 0x53:
        return "Shutdown"
    default:
        return "None"
    }
}
