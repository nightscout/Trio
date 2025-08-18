let CommandHistoryBloodGlucose: UInt16 = (UInt16(DanaPacketType.TYPE_RESPONSE & 0xFF) << 8) +
    UInt16(DanaPacketType.OPCODE_REVIEW__BLOOD_GLUCOSE & 0xFF)

func generatePacketHistoryBloodGlucose(options: PacketHistoryBase) -> DanaGeneratePacket {
    DanaGeneratePacket(
        opCode: DanaPacketType.OPCODE_REVIEW__BLOOD_GLUCOSE,
        data: generatePacketHistoryData(options: options)
    )
}
