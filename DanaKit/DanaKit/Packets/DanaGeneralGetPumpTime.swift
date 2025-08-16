struct PacketGeneralGetPumpTime {
    var time: Date
}

let CommandGeneralGetPumpTime: UInt16 = (UInt16(DanaPacketType.TYPE_RESPONSE & 0xFF) << 8) +
    UInt16(DanaPacketType.OPCODE_OPTION__GET_PUMP_TIME & 0xFF)

func generatePacketGeneralGetPumpTime() -> DanaGeneratePacket {
    DanaGeneratePacket(
        opCode: DanaPacketType.OPCODE_OPTION__GET_PUMP_TIME,
        data: nil
    )
}

func parsePacketGeneralGetPumpTime(data: Data, usingUtc _: Bool?) -> DanaParsePacket<PacketGeneralGetPumpTime> {
    let time = DateComponents(
        year: 2000 + Int(data[DataStart]),
        month: Int(data[DataStart + 1]),
        day: Int(data[DataStart + 2]),
        hour: Int(data[DataStart + 3]),
        minute: Int(data[DataStart + 4]),
        second: Int(data[DataStart + 5])
    )

    guard let parsedTime = Calendar.current.date(from: time) else {
        // Handle error, if needed
        return DanaParsePacket(success: false, rawData: data, data: nil)
    }

    return DanaParsePacket(
        success: true,
        rawData: data,
        data: PacketGeneralGetPumpTime(time: parsedTime)
    )
}
