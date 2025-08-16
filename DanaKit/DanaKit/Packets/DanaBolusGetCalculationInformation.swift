struct PacketBolusGetCalculationInformation {
    var currentBg: UInt16
    var carbohydrate: UInt16
    var currentTarget: UInt16
    var currentCIR: UInt16
    var currentCF: UInt16

    /** 0 = mg/dl, 1 = mmol/L */
    var units: UInt8
}

let CommandBolusGetCalculationInformation: UInt16 = (UInt16(DanaPacketType.TYPE_RESPONSE & 0xFF) << 8) +
    UInt16(DanaPacketType.OPCODE_BOLUS__GET_CALCULATION_INFORMATION & 0xFF)

func generatePacketBolusGetCalculationInformation() -> DanaGeneratePacket {
    DanaGeneratePacket(opCode: DanaPacketType.OPCODE_BOLUS__GET_CALCULATION_INFORMATION, data: nil)
}

func parsePacketBolusGetCalculationInformation(
    data: Data,
    usingUtc _: Bool?
) -> DanaParsePacket<PacketBolusGetCalculationInformation> {
    let currentBg = data.uint16(at: DataStart + 1)
    let carbohydrate = data.uint16(at: DataStart + 3)
    let currentTarget = data.uint16(at: DataStart + 5)
    let currentCIR = data.uint16(at: DataStart + 7)
    let currentCF = data.uint16(at: DataStart + 9)
    let units = data[DataStart + 11]

    return DanaParsePacket(success: data[DataStart] == 0, rawData: data, data: PacketBolusGetCalculationInformation(
        currentBg: units == 1 ? currentBg / 100 : currentBg,
        carbohydrate: carbohydrate,
        currentTarget: units == 1 ? currentTarget / 100 : currentTarget,
        currentCIR: currentCIR,
        currentCF: units == 1 ? currentCF / 100 : currentCF,
        units: units
    ))
}
