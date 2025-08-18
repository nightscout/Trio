struct PacketBasalGetProfileNumber {
    let activeProfile: UInt8
}

let CommandBasalGetProfileNumber: UInt16 = (UInt16(DanaPacketType.TYPE_RESPONSE & 0xFF) << 8) +
    UInt16(DanaPacketType.OPCODE_BASAL__GET_PROFILE_BASAL_RATE & 0xFF)

func generatePacketBasalGetProfileNumber() -> DanaGeneratePacket {
    DanaGeneratePacket(opCode: DanaPacketType.OPCODE_BASAL__GET_PROFILE_BASAL_RATE, data: nil)
}

func parsePacketBasalGetProfileNumber(data: Data, usingUtc _: Bool?) -> DanaParsePacket<PacketBasalGetProfileNumber> {
    DanaParsePacket(success: true, rawData: data, data: PacketBasalGetProfileNumber(activeProfile: data[DataStart]))
}
