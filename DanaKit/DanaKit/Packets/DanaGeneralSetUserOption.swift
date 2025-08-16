public struct PacketGeneralSetUserOption {
    var isTimeDisplay24H: Bool
    var isButtonScrollOnOff: Bool
    var beepAndAlarm: UInt8
    var lcdOnTimeInSec: UInt8
    var backlightOnTimeInSec: UInt8
    var selectedLanguage: UInt8
    var units: UInt8
    var shutdownHour: UInt8
    var lowReservoirRate: UInt8
    var cannulaVolume: UInt16
    var refillAmount: UInt16

    /** Only on hw v7+ */
    var targetBg: UInt16?
}

let CommandGeneralSetUserOption: UInt16 = (UInt16(DanaPacketType.TYPE_RESPONSE & 0xFF) << 8) +
    UInt16(DanaPacketType.OPCODE_OPTION__SET_USER_OPTION & 0xFF)

func generatePacketGeneralSetUserOption(options: PacketGeneralSetUserOption) -> DanaGeneratePacket {
    var data = Data(count: options.targetBg != nil ? 15 : 13)
    data[0] = options.isTimeDisplay24H ? 0x00 : 0x01
    data[1] = options.isButtonScrollOnOff ? 0x01 : 0x00
    data[2] = options.beepAndAlarm
    data[3] = options.lcdOnTimeInSec
    data[4] = options.backlightOnTimeInSec
    data[5] = options.selectedLanguage
    data[6] = options.units
    data[7] = options.shutdownHour
    data[8] = options.lowReservoirRate
    data[9] = UInt8(options.cannulaVolume & 0xFF)
    data[10] = UInt8((options.cannulaVolume >> 8) & 0xFF)
    data[11] = UInt8(options.refillAmount & 0xFF)
    data[12] = UInt8((options.refillAmount >> 8) & 0xFF)

    if let targetBg = options.targetBg {
        data[13] = UInt8(targetBg & 0xFF)
        data[14] = UInt8((targetBg >> 8) & 0xFF)
    }

    return DanaGeneratePacket(
        opCode: DanaPacketType.OPCODE_OPTION__SET_USER_OPTION,
        data: data
    )
}

func parsePacketGeneralSetUserOption(data: Data, usingUtc _: Bool?) -> DanaParsePacket<Any> {
    DanaParsePacket(
        success: data[DataStart] == 0,
        rawData: data,
        data: nil
    )
}
