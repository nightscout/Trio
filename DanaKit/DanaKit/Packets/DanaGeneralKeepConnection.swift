let CommandGeneralKeepConnection: UInt16 = (UInt16(DanaPacketType.TYPE_RESPONSE & 0xFF) << 8) +
    UInt16(DanaPacketType.OPCODE_ETC__KEEP_CONNECTION & 0xFF)

func generatePacketGeneralKeepConnection() -> DanaGeneratePacket {
    DanaGeneratePacket(
        opCode: DanaPacketType.OPCODE_ETC__KEEP_CONNECTION,
        data: nil
    )
}

func parsePacketGeneralKeepConnection(data: Data, usingUtc _: Bool?) -> DanaParsePacket<Any> {
    DanaParsePacket(
        success: data[DataStart] == 0,
        rawData: data,
        data: nil
    )
}
