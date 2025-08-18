let CommandHistoryTemporary: UInt16 = (UInt16(DanaPacketType.TYPE_RESPONSE & 0xFF) << 8) +
    UInt16(DanaPacketType.OPCODE_REVIEW__TEMPORARY & 0xFF)

func generatePacketHistoryTemporary(options: PacketHistoryBase) -> DanaGeneratePacket {
    DanaGeneratePacket(
        opCode: DanaPacketType.OPCODE_REVIEW__TEMPORARY,
        data: generatePacketHistoryData(options: options)
    )
}
