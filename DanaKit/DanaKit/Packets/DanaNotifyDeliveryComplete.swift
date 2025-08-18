struct PacketNotifyDeliveryComplete {
    var deliveredInsulin: Double
}

let CommandNotifyDeliveryComplete: UInt16 = (UInt16(DanaPacketType.TYPE_NOTIFY & 0xFF) << 8) +
    UInt16(DanaPacketType.OPCODE_NOTIFY__DELIVERY_COMPLETE & 0xFF)

func parsePacketNotifyDeliveryComplete(data: Data, usingUtc _: Bool?) -> DanaParsePacket<PacketNotifyDeliveryComplete> {
    DanaParsePacket(
        success: true,
        notifyType: CommandNotifyDeliveryComplete,
        rawData: data,
        data: PacketNotifyDeliveryComplete(
            deliveredInsulin: Double(data.uint16(at: DataStart)) / 100
        )
    )
}
