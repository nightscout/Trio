struct PacketBolusGet24CIRCFArray {
    var unit: UInt8 // Change to the appropriate data type in Swift

    /** Length: 24, value per hour. insulin to carbohydrate ratio */
    var ic: [UInt16]

    /** Length: 24, value per hour. insulin sensitivity factor */
    var isf: [UInt16]
}

let CommandBolusGet24CIRCFArray: UInt16 = (UInt16(DanaPacketType.TYPE_RESPONSE & 0xFF) << 8) +
    UInt16(DanaPacketType.OPCODE_BOLUS__GET_24_CIR_CF_ARRAY & 0xFF)

func generatePacketBolusGet24CIRCFArray() -> DanaGeneratePacket {
    DanaGeneratePacket(opCode: DanaPacketType.OPCODE_BOLUS__GET_24_CIR_CF_ARRAY, data: nil)
}

func parsePacketBolusGet24CIRCFArray(data: Data, usingUtc _: Bool?) -> DanaParsePacket<PacketBolusGet24CIRCFArray> {
    var isf: [UInt16] = []
    var ic: [UInt16] = []
    let unit = data[DataStart]

    for i in 0 ..< 24 {
        ic.append(data.uint16(at: DataStart + 1 + 2 * i))
        isf.append(data.uint16(at: DataStart + 49 + 2 * i) / (unit == 0 ? 1 : 100))
    }

    return DanaParsePacket(
        success: unit == 0 || unit == 1,
        rawData: data,
        data: PacketBolusGet24CIRCFArray(unit: unit, ic: ic, isf: isf)
    )
}
