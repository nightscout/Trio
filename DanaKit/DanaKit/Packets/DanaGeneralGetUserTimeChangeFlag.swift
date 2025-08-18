struct PacketGeneralGetUserTimeChangeFlag {
    var userTimeChangeFlag: UInt8
}

let CommandGeneralGetUserTimeChangeFlag: UInt16 = (UInt16(DanaPacketType.TYPE_RESPONSE & 0xFF) << 8) +
    UInt16(DanaPacketType.OPCODE_REVIEW__GET_USER_TIME_CHANGE_FLAG & 0xFF)

func generatePacketGeneralGetUserTimeChangeFlag() -> DanaGeneratePacket {
    DanaGeneratePacket(
        opCode: DanaPacketType.OPCODE_REVIEW__GET_USER_TIME_CHANGE_FLAG,
        data: nil
    )
}

func parsePacketGeneralGetUserTimeChangeFlag(
    data: Data,
    usingUtc _: Bool?
) -> DanaParsePacket<PacketGeneralGetUserTimeChangeFlag> {
    guard data.count >= 3 else {
        return DanaParsePacket(
            success: false,
            rawData: data,
            data: PacketGeneralGetUserTimeChangeFlag(userTimeChangeFlag: 0)
        )
    }

    return DanaParsePacket(
        success: true,
        rawData: data,
        data: PacketGeneralGetUserTimeChangeFlag(userTimeChangeFlag: data[DataStart])
    )
}
