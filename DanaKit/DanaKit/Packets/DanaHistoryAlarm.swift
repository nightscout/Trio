let CommandHistoryAlarm: UInt16 = (UInt16(DanaPacketType.TYPE_RESPONSE & 0xFF) << 8) +
    UInt16(DanaPacketType.OPCODE_REVIEW__ALARM & 0xFF)

func generatePacketHistoryAlarm(options: PacketHistoryBase) -> DanaGeneratePacket {
    DanaGeneratePacket(
        opCode: DanaPacketType.OPCODE_REVIEW__ALARM,
        data: generatePacketHistoryData(options: options)
    )
}
