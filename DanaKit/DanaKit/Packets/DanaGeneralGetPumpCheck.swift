struct PacketGeneralGetPumpCheck {
    let hwModel: UInt8
    let protocolCode: UInt8
    let productCode: UInt8
}

let CommandGeneralGetPumpCheck: UInt16 = (UInt16(DanaPacketType.TYPE_RESPONSE & 0xFF) << 8) +
    UInt16(DanaPacketType.OPCODE_REVIEW__GET_PUMP_CHECK & 0xFF)

func generatePacketGeneralGetPumpCheck() -> DanaGeneratePacket {
    DanaGeneratePacket(opCode: DanaPacketType.OPCODE_REVIEW__GET_PUMP_CHECK, data: nil)
}

func parsePacketGeneralGetPumpCheck(data: Data, usingUtc _: Bool?) -> DanaParsePacket<PacketGeneralGetPumpCheck> {
    DanaParsePacket(
        success: data[4] < 4, // Unsupported hardware...
        rawData: data,
        data: PacketGeneralGetPumpCheck(
            hwModel: data[DataStart],
            protocolCode: data[DataStart + 1],
            productCode: data[DataStart + 2]
        )
    )
}
