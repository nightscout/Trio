let CommandHistoryDaily: UInt16 = (UInt16(DanaPacketType.TYPE_RESPONSE & 0xFF) << 8) +
    UInt16(DanaPacketType.OPCODE_REVIEW__DAILY & 0xFF)

func generatePacketHistoryDaily(options: PacketHistoryBase) -> DanaGeneratePacket {
    DanaGeneratePacket(
        opCode: DanaPacketType.OPCODE_REVIEW__DAILY,
        data: generatePacketHistoryData(options: options)
    )
}
