struct PacketBolusSet24CIRCFArray {
    /** 0 => mg/dl, 1 => mmol/L */
    var unit: UInt8
    var ic: [Double]
    var isf: [UInt16]
}

let CommandBolusSet24CIRCFArray: UInt16 = (UInt16(DanaPacketType.TYPE_RESPONSE & 0xFF) << 8) +
    UInt16(DanaPacketType.OPCODE_BOLUS__SET_24_CIR_CF_ARRAY & 0xFF)

func generatePacketBolusSet24CIRCFArray(options: PacketBolusSet24CIRCFArray) throws -> DanaGeneratePacket {
    guard options.isf.count == 24, options.ic.count == 24 else {
        throw NSError(domain: "INVALID_LENGTH", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid length isf or ic"])
    }

    var adjustedISF = options.isf
    if options.unit == 1 {
        adjustedISF = options.isf.map { $0 * 100 }
    }

    var data = Data(count: 96)
    for i in 0 ..< 24 {
        let roundedIC = UInt16(Double(options.ic[i]).rounded())
        let roundedISF = UInt16(Double(adjustedISF[i]).rounded())

        data[i * 2] = UInt8(roundedIC & 0xFF)
        data[i * 2 + 1] = UInt8((roundedIC >> 8) & 0xFF)

        data[i * 2 + 48] = UInt8(roundedISF & 0xFF)
        data[i * 2 + 49] = UInt8((roundedISF >> 8) & 0xFF)
    }

    return DanaGeneratePacket(opCode: DanaPacketType.OPCODE_BOLUS__SET_24_CIR_CF_ARRAY, data: data)
}

func parsePacketBolusSet24CIRCFArray(data: Data, usingUtc _: Bool?) -> DanaParsePacket<Any> {
    DanaParsePacket(success: data[DataStart] == 0, rawData: data, data: nil)
}
