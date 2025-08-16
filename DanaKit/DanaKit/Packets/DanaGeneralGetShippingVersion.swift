struct PacketGeneralGetShippingVersion {
    var bleModel: String
}

let CommandGeneralGetShippingVersion: UInt16 = (UInt16(DanaPacketType.TYPE_RESPONSE & 0xFF) << 8) +
    UInt16(DanaPacketType.OPCODE_GENERAL__GET_SHIPPING_VERSION & 0xFF)

func generatePacketGeneralGetShippingVersion() -> DanaGeneratePacket {
    DanaGeneratePacket(
        opCode: DanaPacketType.OPCODE_GENERAL__GET_SHIPPING_VERSION,
        data: nil
    )
}

func parsePacketGeneralGetShippingVersion(data: Data, usingUtc _: Bool?) -> DanaParsePacket<PacketGeneralGetShippingVersion> {
    DanaParsePacket(
        success: true,
        rawData: data,
        data: PacketGeneralGetShippingVersion(
            bleModel: String(data: data.subdata(in: DataStart ..< data.count), encoding: .utf8) ?? ""
        )
    )
}
