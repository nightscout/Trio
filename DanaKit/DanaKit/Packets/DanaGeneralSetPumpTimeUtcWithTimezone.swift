struct PacketGeneralSetPumpTimeUtcWithTimezone {
    var time: Date
    var zoneOffset: UInt8
}

let CommandGeneralSetPumpTimeUtcWithTimezone: UInt16 = (UInt16(DanaPacketType.TYPE_RESPONSE & 0xFF) << 8) +
    UInt16(DanaPacketType.OPCODE_OPTION__SET_PUMP_UTC_AND_TIME_ZONE & 0xFF)

func generatePacketGeneralSetPumpTimeUtcWithTimezone(options: PacketGeneralSetPumpTimeUtcWithTimezone) -> DanaGeneratePacket {
    var data = Data(count: 7)
    data.addDate(at: 0, date: options.time)
    data[6] = options.zoneOffset

    return DanaGeneratePacket(
        opCode: DanaPacketType.OPCODE_OPTION__SET_PUMP_UTC_AND_TIME_ZONE,
        data: data
    )
}

func parsePacketGeneralSetPumpTimeUtcWithTimezone(data: Data, usingUtc _: Bool?) -> DanaParsePacket<Any> {
    DanaParsePacket(
        success: data[DataStart] == 0,
        rawData: data,
        data: nil
    )
}
