let CommandHistoryPrime: UInt16 = (UInt16(DanaPacketType.TYPE_RESPONSE & 0xFF) << 8) +
    UInt16(DanaPacketType.OPCODE_REVIEW__PRIME & 0xFF)

func generatePacketHistoryPrime(options: PacketHistoryBase) -> DanaGeneratePacket {
    DanaGeneratePacket(
        opCode: DanaPacketType.OPCODE_REVIEW__PRIME,
        data: generatePacketHistoryData(options: options)
    )
}
