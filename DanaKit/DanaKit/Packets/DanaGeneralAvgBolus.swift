struct PacketGeneralAvgBolus {
    var bolusAvg03days: Double
    var bolusAvg07days: Double
    var bolusAvg14days: Double
    var bolusAvg21days: Double
    var bolusAvg28days: Double
}

let CommandGeneralAvgBolus: UInt16 = (UInt16(DanaPacketType.TYPE_RESPONSE & 0xFF) << 8) +
    UInt16(DanaPacketType.OPCODE_REVIEW__BOLUS_AVG & 0xFF)

func generatePacketGeneralAvgBolus() -> DanaGeneratePacket {
    DanaGeneratePacket(opCode: DanaPacketType.OPCODE_REVIEW__BOLUS_AVG, data: nil)
}

func parsePacketGeneralAvgBolus(data: Data, usingUtc _: Bool?) -> DanaParsePacket<PacketGeneralAvgBolus> {
    let checkValue = (Double(1 & (0x0000_00FF << 8)) + Double(1 & 0x0000_00FF)) / 100

    let bolusAvg03days = Double(data.uint16(at: DataStart)) / 100
    let bolusAvg07days = Double(data.uint16(at: DataStart)) / 100
    let bolusAvg14days = Double(data.uint16(at: DataStart)) / 100
    let bolusAvg21days = Double(data.uint16(at: DataStart)) / 100
    let bolusAvg28days = Double(data.uint16(at: DataStart)) / 100

    return DanaParsePacket(
        success:
        bolusAvg03days != checkValue &&
            bolusAvg07days != checkValue &&
            bolusAvg14days != checkValue &&
            bolusAvg21days != checkValue &&
            bolusAvg28days != checkValue,
        rawData: data,
        data: PacketGeneralAvgBolus(
            bolusAvg03days: bolusAvg03days,
            bolusAvg07days: bolusAvg07days,
            bolusAvg14days: bolusAvg14days,
            bolusAvg21days: bolusAvg21days,
            bolusAvg28days: bolusAvg28days
        )
    )
}
