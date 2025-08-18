public enum BolusSpeed: UInt8 {
    case speed12 = 0
    case speed30 = 1
    case speed60 = 2

    static func all() -> [Int] {
        [Int(BolusSpeed.speed12.rawValue), Int(BolusSpeed.speed30.rawValue), Int(BolusSpeed.speed60.rawValue)]
    }

    func format() -> String {
        switch self {
        case .speed12:
            return LocalizedString("12 sec/E", comment: "Dana bolus speed 12u per min")
        case .speed30:
            return LocalizedString("30 sec/E", comment: "Dana bolus speed 30u per min")
        case .speed60:
            return LocalizedString("60 sec/E", comment: "Dana bolus speed 60u per min")
        }
    }
}

struct PacketBolusStart {
    var amount: Double
    var speed: BolusSpeed
}

let CommandBolusStart: UInt16 = (UInt16(DanaPacketType.TYPE_RESPONSE & 0xFF) << 8) +
    UInt16(DanaPacketType.OPCODE_BOLUS__SET_STEP_BOLUS_START & 0xFF)

func generatePacketBolusStart(options: PacketBolusStart) -> DanaGeneratePacket {
    let bolusRate = UInt16(options.amount * 100)
    var data = Data(count: 3)
    data[0] = UInt8(bolusRate & 0xFF)
    data[1] = UInt8((bolusRate >> 8) & 0xFF)
    data[2] = options.speed.rawValue

    return DanaGeneratePacket(opCode: DanaPacketType.OPCODE_BOLUS__SET_STEP_BOLUS_START, data: data)
}

func parsePacketBolusStart(data: Data, usingUtc _: Bool?) -> DanaParsePacket<Any> {
    DanaParsePacket(success: data[DataStart] == 0, rawData: data, data: nil)
}

/**
 * Error codes:
 * 0x01 => Pump suspended
 * 0x04 => Bolus timeout active
 * 0x10 => Max bolus violation
 * 0x20 => Command error (Unknown what this error means)
 * 0x40 => Speed error (Can only happen during development)
 * 0x80 => Insulin limit violation
 */
func transformBolusError(code: UInt8) -> DanaKitPumpManagerError {
    switch code {
    case 0x01:
        return DanaKitPumpManagerError.pumpSuspended
    case 0x04:
        return DanaKitPumpManagerError.bolusTimeoutActive
    case 0x10:
        return DanaKitPumpManagerError.bolusMaxViolation
    case 0x20:
        return DanaKitPumpManagerError.unknown("bolusCommandError")
    case 0x40:
        return DanaKitPumpManagerError.unknown("Invalid bolus speed error")
    case 0x80:
        return DanaKitPumpManagerError.bolusInsulinLimitViolation
    default:
        return DanaKitPumpManagerError.unknown("Unknown error: \(code)")
    }
}
