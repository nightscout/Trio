struct PacketGeneralGetPumpDecRatio {
    var decRatio: UInt8
}

let CommandGeneralGetPumpDecRatio: UInt16 = (UInt16(DanaPacketType.TYPE_RESPONSE & 0xFF) << 8) +
    UInt16(DanaPacketType.OPCODE_REVIEW__GET_PUMP_DEC_RATIO & 0xFF)

func generatePacketGeneralGetPumpDecRatio() -> DanaGeneratePacket {
    DanaGeneratePacket(
        opCode: DanaPacketType.OPCODE_REVIEW__GET_PUMP_DEC_RATIO,
        data: nil
    )
}

func parsePacketGeneralGetPumpDecRatio(data: Data, usingUtc _: Bool?) -> DanaParsePacket<PacketGeneralGetPumpDecRatio> {
    DanaParsePacket(
        success: true,
        rawData: data,
        data: PacketGeneralGetPumpDecRatio(
            decRatio: data[DataStart] * 5
        )
    )
}
