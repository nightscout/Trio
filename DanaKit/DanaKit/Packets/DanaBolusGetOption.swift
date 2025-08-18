struct PacketBolusGetOption {
    var isExtendedBolusEnabled: Bool
    var bolusCalculationOption: UInt8
    var missedBolusConfig: UInt8
    var missedBolus01StartHour: UInt8
    var missedBolus01StartMinute: UInt8
    var missedBolus01EndHour: UInt8
    var missedBolus01EndMinute: UInt8
    var missedBolus02StartHour: UInt8
    var missedBolus02StartMinute: UInt8
    var missedBolus02EndHour: UInt8
    var missedBolus02EndMinute: UInt8
    var missedBolus03StartHour: UInt8
    var missedBolus03StartMinute: UInt8
    var missedBolus03EndHour: UInt8
    var missedBolus03EndMinute: UInt8
    var missedBolus04StartHour: UInt8
    var missedBolus04StartMinute: UInt8
    var missedBolus04EndHour: UInt8
    var missedBolus04EndMinute: UInt8
}

let CommandBolusGetOption: UInt16 = (UInt16(DanaPacketType.TYPE_RESPONSE & 0xFF) << 8) +
    UInt16(DanaPacketType.OPCODE_BOLUS__GET_BOLUS_OPTION & 0xFF)

func generatePacketBolusGetOption() -> DanaGeneratePacket {
    DanaGeneratePacket(opCode: DanaPacketType.OPCODE_BOLUS__GET_BOLUS_OPTION, data: nil)
}

func parsePacketBolusGetOption(data: Data, usingUtc _: Bool?) -> DanaParsePacket<PacketBolusGetOption> {
    let isExtendedBolusEnabled = data[DataStart] == 1

    return DanaParsePacket(success: isExtendedBolusEnabled, rawData: data, data: PacketBolusGetOption(
        isExtendedBolusEnabled: isExtendedBolusEnabled,
        bolusCalculationOption: data[DataStart + 1],
        missedBolusConfig: data[DataStart + 2],
        missedBolus01StartHour: data[DataStart + 3],
        missedBolus01StartMinute: data[DataStart + 4],
        missedBolus01EndHour: data[DataStart + 5],
        missedBolus01EndMinute: data[DataStart + 6],
        missedBolus02StartHour: data[DataStart + 7],
        missedBolus02StartMinute: data[DataStart + 8],
        missedBolus02EndHour: data[DataStart + 9],
        missedBolus02EndMinute: data[DataStart + 10],
        missedBolus03StartHour: data[DataStart + 11],
        missedBolus03StartMinute: data[DataStart + 12],
        missedBolus03EndHour: data[DataStart + 13],
        missedBolus03EndMinute: data[DataStart + 14],
        missedBolus04StartHour: data[DataStart + 15],
        missedBolus04StartMinute: data[DataStart + 16],
        missedBolus04EndHour: data[DataStart + 17],
        missedBolus04EndMinute: data[DataStart + 18]
    ))
}
