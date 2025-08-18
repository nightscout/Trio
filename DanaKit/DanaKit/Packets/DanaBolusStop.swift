let CommandBolusStop: UInt16 = (UInt16(DanaPacketType.TYPE_RESPONSE & 0xFF) << 8) +
    UInt16(DanaPacketType.OPCODE_BOLUS__SET_STEP_BOLUS_STOP & 0xFF)

func generatePacketBolusStop() -> DanaGeneratePacket {
    DanaGeneratePacket(opCode: DanaPacketType.OPCODE_BOLUS__SET_STEP_BOLUS_STOP, data: nil)
}

func parsePacketBolusStop(data: Data, usingUtc _: Bool?) -> DanaParsePacket<Any> {
    DanaParsePacket(success: data[DataStart] == 0, rawData: data, data: nil)
}
