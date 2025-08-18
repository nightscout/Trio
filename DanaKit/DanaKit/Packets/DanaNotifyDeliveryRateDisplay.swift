struct PacketNotifyDeliveryRateDisplay {
    var deliveredInsulin: Double
}

let CommandNotifyDeliveryRateDisplay: UInt16 = (UInt16(DanaPacketType.TYPE_NOTIFY & 0xFF) << 8) +
    UInt16(DanaPacketType.OPCODE_NOTIFY__DELIVERY_RATE_DISPLAY & 0xFF)

func parsePacketNotifyDeliveryRateDisplay(data: Data, usingUtc _: Bool?) -> DanaParsePacket<PacketNotifyDeliveryRateDisplay> {
    DanaParsePacket(
        success: true,
        notifyType: CommandNotifyDeliveryRateDisplay,
        rawData: data,
        data: PacketNotifyDeliveryRateDisplay(
            deliveredInsulin: Double(data.uint16(at: DataStart)) / 100
        )
    )
}
