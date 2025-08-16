struct PacketBolusSetOption {
    var extendedBolusOptionOnOff: UInt8
    var bolusCalculationOption: UInt8
    var missedBolusConfig: UInt8
    var missedBolus01StartHour: UInt8
    var missedBolus01StartMin: UInt8
    var missedBolus01EndHour: UInt8
    var missedBolus01EndMin: UInt8
    var missedBolus02StartHour: UInt8
    var missedBolus02StartMin: UInt8
    var missedBolus02EndHour: UInt8
    var missedBolus02EndMin: UInt8
    var missedBolus03StartHour: UInt8
    var missedBolus03StartMin: UInt8
    var missedBolus03EndHour: UInt8
    var missedBolus03EndMin: UInt8
    var missedBolus04StartHour: UInt8
    var missedBolus04StartMin: UInt8
    var missedBolus04EndHour: UInt8
    var missedBolus04EndMin: UInt8
}

let CommandBolusSetOption: UInt16 = (UInt16(DanaPacketType.TYPE_RESPONSE & 0xFF) << 8) +
    UInt16(DanaPacketType.OPCODE_BOLUS__SET_BOLUS_OPTION & 0xFF)

func generatePacketBolusSetOption(options: PacketBolusSetOption) -> DanaGeneratePacket {
    var data = Data(count: 19)
    data[0] = options.extendedBolusOptionOnOff
    data[1] = options.bolusCalculationOption
    data[2] = options.missedBolusConfig
    data[3] = options.missedBolus01StartHour
    data[4] = options.missedBolus01StartMin
    data[5] = options.missedBolus01EndHour
    data[6] = options.missedBolus01EndMin
    data[7] = options.missedBolus02StartHour
    data[8] = options.missedBolus02StartMin
    data[9] = options.missedBolus02EndHour
    data[10] = options.missedBolus02EndMin
    data[11] = options.missedBolus03StartHour
    data[12] = options.missedBolus03StartMin
    data[13] = options.missedBolus03EndHour
    data[14] = options.missedBolus03EndMin
    data[15] = options.missedBolus04StartHour
    data[16] = options.missedBolus04StartMin
    data[17] = options.missedBolus04EndHour
    data[18] = options.missedBolus04EndMin

    return DanaGeneratePacket(opCode: DanaPacketType.OPCODE_BOLUS__SET_BOLUS_OPTION, data: data)
}

func parsePacketBolusSetOption(data: Data, usingUtc _: Bool?) -> DanaParsePacket<Any> {
    DanaParsePacket(success: data[DataStart] == 0, rawData: data, data: nil)
}
