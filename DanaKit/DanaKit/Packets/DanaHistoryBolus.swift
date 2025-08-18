let CommandHistoryBolus: UInt16 = (UInt16(DanaPacketType.TYPE_RESPONSE & 0xFF) << 8) +
    UInt16(DanaPacketType.OPCODE_REVIEW__BOLUS & 0xFF)

func generatePacketHistoryBolus(options: PacketHistoryBase) -> DanaGeneratePacket {
    DanaGeneratePacket(
        opCode: DanaPacketType.OPCODE_REVIEW__BOLUS,
        data: generatePacketHistoryData(options: options)
    )
}
