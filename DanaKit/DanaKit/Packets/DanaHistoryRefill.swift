let CommandHistoryRefill: UInt16 = (UInt16(DanaPacketType.TYPE_RESPONSE & 0xFF) << 8) +
    UInt16(DanaPacketType.OPCODE_REVIEW__REFILL & 0xFF)

func generatePacketHistoryRefill(options: PacketHistoryBase) -> DanaGeneratePacket {
    DanaGeneratePacket(
        opCode: DanaPacketType.OPCODE_REVIEW__REFILL,
        data: generatePacketHistoryData(options: options)
    )
}
