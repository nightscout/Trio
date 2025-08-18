let CommandHistoryCarbohydrates: UInt16 = (UInt16(DanaPacketType.TYPE_RESPONSE & 0xFF) << 8) +
    UInt16(DanaPacketType.OPCODE_REVIEW__CARBOHYDRATE & 0xFF)

func generatePacketHistoryCarbohydrates(options: PacketHistoryBase) -> DanaGeneratePacket {
    DanaGeneratePacket(
        opCode: DanaPacketType.OPCODE_REVIEW__CARBOHYDRATE,
        data: generatePacketHistoryData(options: options)
    )
}
