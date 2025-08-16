struct PacketGeneralGetShippingInformation {
    var serialNumber: String
    var shippingCountry: String
    var shippingDate: Date
}

let CommandGeneralGetShippingInformation: UInt16 = (UInt16(DanaPacketType.TYPE_RESPONSE & 0xFF) << 8) +
    UInt16(DanaPacketType.OPCODE_REVIEW__GET_SHIPPING_INFORMATION & 0xFF)

func generatePacketGeneralGetShippingInformation() -> DanaGeneratePacket {
    DanaGeneratePacket(
        opCode: DanaPacketType.OPCODE_REVIEW__GET_SHIPPING_INFORMATION,
        data: nil
    )
}

func parsePacketGeneralGetShippingInformation(
    data: Data,
    usingUtc _: Bool?
) -> DanaParsePacket<PacketGeneralGetShippingInformation> {
    guard data.count >= 18 else {
        return DanaParsePacket(
            success: false,
            rawData: data,
            data: PacketGeneralGetShippingInformation(
                serialNumber: "",
                shippingCountry: "",
                shippingDate: Date()
            )
        )
    }

    let serialNumberData = data.subdata(in: DataStart ..< DataStart + 10)
    let shippingCountryData = data.subdata(in: DataStart + 10 ..< DataStart + 13)

    let serialNumber = String(data: serialNumberData, encoding: .utf8) ?? ""
    let shippingCountry = String(data: shippingCountryData, encoding: .utf8) ?? ""

    let shippingDate = DateComponents(
        calendar: .current,
        year: 2000 + Int(data[DataStart + 13]),
        month: Int(data[DataStart + 14]) - 1,
        day: Int(data[DataStart + 15]),
        hour: 0,
        minute: 0,
        second: 0
    )

    guard let parsedDate = Calendar.current.date(from: shippingDate) else {
        // Handle error, if needed
        return DanaParsePacket(success: false, rawData: data, data: nil)
    }

    return DanaParsePacket(
        success: true,
        rawData: data,
        data: PacketGeneralGetShippingInformation(
            serialNumber: serialNumber,
            shippingCountry: shippingCountry,
            shippingDate: parsedDate
        )
    )
}
