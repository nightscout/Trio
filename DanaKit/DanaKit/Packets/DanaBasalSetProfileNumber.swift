struct PacketBasalSetProfileNumber {
    let profileNumber: UInt8
}

let CommandBasalSetProfileNumber: UInt16 = (UInt16(DanaPacketType.TYPE_RESPONSE & 0xFF) << 8) +
    UInt16(DanaPacketType.OPCODE_BASAL__SET_PROFILE_NUMBER & 0xFF)
func generatePacketBasalSetProfileNumber(options: PacketBasalSetProfileNumber) -> DanaGeneratePacket {
    let data = Data([options.profileNumber & 0xFF])

    return DanaGeneratePacket(opCode: DanaPacketType.OPCODE_BASAL__SET_PROFILE_NUMBER, data: data)
}

func parsePacketBasalSetProfileNumber(data: Data, usingUtc _: Bool?) -> DanaParsePacket<Any> {
    DanaParsePacket(success: data[DataStart] == 0, rawData: data, data: nil)
}
