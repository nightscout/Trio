let CommandBasalCancelTemporary: UInt16 = (UInt16(DanaPacketType.TYPE_RESPONSE & 0xFF) << 8) +
    UInt16(DanaPacketType.OPCODE_BASAL__CANCEL_TEMPORARY_BASAL & 0xFF)

func generatePacketBasalCancelTemporary() -> DanaGeneratePacket {
    DanaGeneratePacket(opCode: DanaPacketType.OPCODE_BASAL__CANCEL_TEMPORARY_BASAL, data: nil)
}

func parsePacketBasalCancelTemporary(data: Data, usingUtc _: Bool?) -> DanaParsePacket<Any> {
    DanaParsePacket(success: data[DataStart] == 0, rawData: data, data: nil)
}
