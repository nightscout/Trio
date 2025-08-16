let CommandHistorySuspend: UInt16 = (UInt16(DanaPacketType.TYPE_RESPONSE & 0xFF) << 8) +
    UInt16(DanaPacketType.OPCODE_REVIEW__SUSPEND & 0xFF)

func generatePacketHistorySuspend(options: PacketHistoryBase) -> DanaGeneratePacket {
    DanaGeneratePacket(
        opCode: DanaPacketType.OPCODE_REVIEW__SUSPEND,
        data: generatePacketHistoryData(options: options)
    )
}
