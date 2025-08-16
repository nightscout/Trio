struct PacketGeneralSetPumpTime {
    var time: Date
}

let CommandGeneralSetPumpTime: UInt16 = (UInt16(DanaPacketType.TYPE_RESPONSE & 0xFF) << 8) +
    UInt16(DanaPacketType.OPCODE_OPTION__SET_PUMP_TIME & 0xFF)

func generatePacketGeneralSetPumpTime(options: PacketGeneralSetPumpTime) -> DanaGeneratePacket {
    var data = Data(count: 6)
    data.addDate(at: 0, date: options.time, utc: false)

    return DanaGeneratePacket(
        opCode: DanaPacketType.OPCODE_OPTION__SET_PUMP_TIME,
        data: data
    )
}

func parsePacketGeneralSetPumpTime(data: Data, usingUtc _: Bool?) -> DanaParsePacket<Any> {
    DanaParsePacket(
        success: data[DataStart] == 0,
        rawData: data,
        data: nil
    )
}
