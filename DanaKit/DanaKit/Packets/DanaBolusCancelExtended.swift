let CommandBolusCancelExtended: UInt16 = (UInt16(DanaPacketType.TYPE_RESPONSE & 0xFF) << 8) +
    UInt16(DanaPacketType.OPCODE_BOLUS__SET_EXTENDED_BOLUS_CANCEL & 0xFF)

func generatePacketBolusCancelExtended() -> DanaGeneratePacket {
    DanaGeneratePacket(opCode: DanaPacketType.OPCODE_BOLUS__SET_EXTENDED_BOLUS_CANCEL, data: nil)
}

func parsePacketBolusCancelExtended(data: Data, usingUtc _: Bool?) -> DanaParsePacket<Any> {
    DanaParsePacket(success: data[DataStart] == 0, rawData: data, data: nil)
}
