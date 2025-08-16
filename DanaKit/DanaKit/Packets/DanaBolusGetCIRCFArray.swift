struct PacketBolusGetCIRCFArray {
    var language: UInt8
    var unit: UInt8

    // CIR
    var morningCIR: UInt16
    var cir02: UInt16
    var afternoonCIR: UInt16
    var cir04: UInt16
    var eveningCIR: UInt16
    var cir06: UInt16
    var nightCIR: UInt16

    // CF
    var morningCF: Float
    var cf02: Float
    var afternoonCF: Float
    var cf04: Float
    var eveningCF: Float
    var cf06: Float
    var nightCF: Float
}

let CommandBolusGetCIRCFArray: UInt16 = (UInt16(DanaPacketType.TYPE_RESPONSE & 0xFF) << 8) +
    UInt16(DanaPacketType.OPCODE_BOLUS__GET_CIR_CF_ARRAY & 0xFF)

func generatePacketBolusGetCIRCFArray() -> DanaGeneratePacket {
    DanaGeneratePacket(opCode: DanaPacketType.OPCODE_BOLUS__GET_CIR_CF_ARRAY, data: nil)
}

func parsePacketBolusGetCIRCFArray(data: Data, usingUtc _: Bool?) -> DanaParsePacket<PacketBolusGetCIRCFArray> {
    let language = data[DataStart]
    let unit = data[DataStart + 1]
    let morningCIR = data.uint16(at: DataStart + 2)
    let cir02 = data.uint16(at: DataStart + 4)
    let afternoonCIR = data.uint16(at: DataStart + 6)
    let cir04 = data.uint16(at: DataStart + 8)
    let eveningCIR = data.uint16(at: DataStart + 10)
    let cir06 = data.uint16(at: DataStart + 12)
    let nightCIR = data.uint16(at: DataStart + 14)

    let divisionFactor = unit == 1 ? 100 : 1
    let morningCF = Float(data.uint16(at: DataStart + 16)) / Float(divisionFactor)
    let cf02 = Float(data.uint16(at: DataStart + 18)) / Float(divisionFactor)
    let afternoonCF = Float(data.uint16(at: DataStart + 20)) / Float(divisionFactor)
    let cf04 = Float(data.uint16(at: DataStart + 22)) / Float(divisionFactor)
    let eveningCF = Float(data.uint16(at: DataStart + 24)) / Float(divisionFactor)
    let cf06 = Float(data.uint16(at: DataStart + 26)) / Float(divisionFactor)
    let nightCF = Float(data.uint16(at: DataStart + 28)) / Float(divisionFactor)

    return DanaParsePacket(success: unit == 0 || unit == 1, rawData: data, data: PacketBolusGetCIRCFArray(
        language: language,
        unit: unit,
        morningCIR: morningCIR,
        cir02: cir02,
        afternoonCIR: afternoonCIR,
        cir04: cir04,
        eveningCIR: eveningCIR,
        cir06: cir06,
        nightCIR: nightCIR,
        morningCF: morningCF,
        cf02: cf02,
        afternoonCF: afternoonCF,
        cf04: cf04,
        eveningCF: eveningCF,
        cf06: cf06,
        nightCF: nightCF
    ))
}
