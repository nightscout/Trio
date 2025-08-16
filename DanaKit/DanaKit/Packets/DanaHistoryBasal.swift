let CommandHistoryBasal: UInt16 = (UInt16(DanaPacketType.TYPE_RESPONSE & 0xFF) << 8) +
    UInt16(DanaPacketType.OPCODE_REVIEW__BASAL & 0xFF)

func generatePacketHistoryBasal(options: PacketHistoryBase) -> DanaGeneratePacket {
    DanaGeneratePacket(
        opCode: DanaPacketType.OPCODE_REVIEW__BASAL,
        data: generatePacketHistoryData(options: options)
    )
}
