struct PacketBasalSetProfileRate {
    var profileNumber: UInt8
    var profileBasalRate: [Double]
}

let CommandBasalSetProfileRate: UInt16 = (UInt16(DanaPacketType.TYPE_RESPONSE & 0xFF) << 8) +
    UInt16(DanaPacketType.OPCODE_BASAL__SET_PROFILE_BASAL_RATE & 0xFF)

func generatePacketBasalSetProfileRate(options: PacketBasalSetProfileRate) throws -> DanaGeneratePacket {
    guard options.profileBasalRate.count == 24 else {
        throw NSError(
            domain: "INVALID_LENGTH",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Invalid basal rate. Expected length = 24"]
        )
    }

    var dataArray = [UInt8](repeating: 0, count: 49)
    dataArray[0] = options.profileNumber

    for i in 0 ..< 24 {
        let rate = UInt16(options.profileBasalRate[i] * 100)
        dataArray[1 + i * 2] = UInt8(rate & 0xFF)
        dataArray[2 + i * 2] = UInt8((rate >> 8) & 0xFF)
    }

    return DanaGeneratePacket(opCode: DanaPacketType.OPCODE_BASAL__SET_PROFILE_BASAL_RATE, data: Data(dataArray))
}

func parsePacketBasalSetProfileRate(data: Data, usingUtc _: Bool?) -> DanaParsePacket<Any> {
    DanaParsePacket(success: data[DataStart] == 0, rawData: data, data: nil)
}
