let CommandBasalSetSuspendOff: UInt16 = (UInt16(DanaPacketType.TYPE_RESPONSE & 0xFF) << 8) +
    UInt16(DanaPacketType.OPCODE_BASAL__SET_SUSPEND_OFF & 0xFF)

func generatePacketBasalSetSuspendOff() -> DanaGeneratePacket {
    DanaGeneratePacket(opCode: DanaPacketType.OPCODE_BASAL__SET_SUSPEND_OFF, data: nil)
}

func parsePacketBasalSetSuspendOff(data: Data, usingUtc _: Bool?) -> DanaParsePacket<Any> {
    DanaParsePacket(success: data[DataStart] == 0, rawData: data, data: nil)
}
