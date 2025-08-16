let CommandBasalSetSuspendOn: UInt16 = (UInt16(DanaPacketType.TYPE_RESPONSE & 0xFF) << 8) +
    UInt16(DanaPacketType.OPCODE_BASAL__SET_SUSPEND_ON & 0xFF)

func generatePacketBasalSetSuspendOn() -> DanaGeneratePacket {
    DanaGeneratePacket(opCode: DanaPacketType.OPCODE_BASAL__SET_SUSPEND_ON, data: nil)
}

func parsePacketBasalSetSuspendOn(data: Data, usingUtc _: Bool?) -> DanaParsePacket<Any> {
    DanaParsePacket(success: data[DataStart] == 0, rawData: data, data: nil)
}
