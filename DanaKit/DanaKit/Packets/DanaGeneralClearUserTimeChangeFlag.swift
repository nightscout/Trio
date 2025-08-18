let CommandGeneralClearUserTimeChangeFlag: UInt16 = (UInt16(DanaPacketType.TYPE_RESPONSE & 0xFF) << 8) +
    UInt16(DanaPacketType.OPCODE_REVIEW__SET_USER_TIME_CHANGE_FLAG_CLEAR & 0xFF)

func generatePacketGeneralClearUserTimeChangeFlag() -> DanaGeneratePacket {
    DanaGeneratePacket(opCode: DanaPacketType.OPCODE_REVIEW__SET_USER_TIME_CHANGE_FLAG_CLEAR, data: nil)
}

func parsePacketGeneralClearUserTimeChangeFlag(data: Data, usingUtc _: Bool?) -> DanaParsePacket<Any> {
    DanaParsePacket(success: data[DataStart] == 0, rawData: data, data: nil)
}
