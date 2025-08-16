let CommandHistoryAll: UInt16 = (UInt16(DanaPacketType.TYPE_RESPONSE & 0xFF) << 8) +
    UInt16(DanaPacketType.OPCODE_REVIEW__ALL_HISTORY & 0xFF)

func generatePacketHistoryAll(options: PacketHistoryBase) -> DanaGeneratePacket {
    DanaGeneratePacket(
        opCode: DanaPacketType.OPCODE_REVIEW__ALL_HISTORY,
        data: generatePacketHistoryData(options: options)
    )
}
