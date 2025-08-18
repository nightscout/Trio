let timeInformationEnhancedEncryption2Lookup: [UInt8] = [
    0,
    0x17 ^ 0x1A,
    0xD1 ^ 0xC0,
    0xAF ^ 0xA9
]

struct EncryptParams {
    var operationCode: UInt8
    var data: Data?
    var deviceName: String
    var enhancedEncryption: UInt8
    var timeSecret: Data
    var passwordSecret: Data
    var passKeySecret: Data
}

func encrypt(_ options: EncryptParams) -> (data: Data, isEncryptionMode: Bool) {
    switch options.operationCode {
    // DANAR_PACKET__OPCODE_ENCRYPTION__PUMP_CHECK
    case 0x00:
        return encodePumpCheckCommand(deviceName: options.deviceName, enhancedEncryption: options.enhancedEncryption)

    // DANAR_PACKET__OPCODE_ENCRYPTION__TIME_INFORMATION
    case 0x01:
        return encodeTimeInformation(
            data: options.data,
            deviceName: options.deviceName,
            enhancedEncryption: options.enhancedEncryption
        )

    // DANAR_PACKET__OPCODE_ENCRYPTION__CHECK_PASSKEY
    case 0xD0:
        return encodeCheckPassKeyCommand(
            data: options.data,
            deviceName: options.deviceName,
            enhancedEncryption: options.enhancedEncryption
        )

    // DANAR_PACKET__OPCODE_ENCRYPTION__PASSKEY_REQUEST
    case 0xD1:
        return encodeRequestCommand(
            operationCode: options.operationCode,
            deviceName: options.deviceName,
            enhancedEncryption: options.enhancedEncryption
        )

    // DANAR_PACKET__OPCODE_ENCRYPTION__GET_PUMP_CHECK
    case 0xF3:
        return encodeRequestCommand(
            operationCode: options.operationCode,
            deviceName: options.deviceName,
            enhancedEncryption: options.enhancedEncryption
        )

    // DANAR_PACKET__OPCODE_ENCRYPTION__GET_EASYMENU_CHECK
    case 0xF4:
        return encodeRequestCommand(
            operationCode: options.operationCode,
            deviceName: options.deviceName,
            enhancedEncryption: options.enhancedEncryption
        )

    default:
        return encodeDefault(options: options)
    }
}

struct EncryptSecondLevelParams {
    var buffer: Data
    var enhancedEncryption: UInt8
    var pairingKey: Data
    var randomPairingKey: Data
    var randomSyncKey: UInt8
    var bleRandomKeys: (UInt8, UInt8, UInt8)
}

func encryptSecondLevel(_ params: inout EncryptSecondLevelParams) -> (randomSyncKey: UInt8, buffer: Data) {
    var updatedRandomSyncKey = params.randomSyncKey

    if params.enhancedEncryption == 1 {
        if params.buffer[0] == 0xA5, params.buffer[1] == 0xA5 {
            params.buffer[0] = 0x7A
            params.buffer[1] = 0x7A
        }

        if params.buffer[params.buffer.count - 2] == 0x5A, params.buffer[params.buffer.count - 1] == 0x5A {
            params.buffer[params.buffer.count - 2] = 0x2E
            params.buffer[params.buffer.count - 1] = 0x2E
        }

        for i in 0 ..< params.buffer.count {
            params.buffer[i] ^= params.pairingKey[0]
            params.buffer[i] &-= updatedRandomSyncKey
            params.buffer[i] = ((params.buffer[i] >> 4) & 0xF) | ((params.buffer[i] & 0xF) << 4)

            params.buffer[i] &+= params.pairingKey[1]
            params.buffer[i] ^= params.pairingKey[2]
            params.buffer[i] = ((params.buffer[i] >> 4) & 0xF) | ((params.buffer[i] & 0xF) << 4)

            params.buffer[i] &-= params.pairingKey[3]
            params.buffer[i] ^= params.pairingKey[4]
            params.buffer[i] = ((params.buffer[i] >> 4) & 0x0F) | ((params.buffer[i] & 0x0F) << 4)

            params.buffer[i] ^= params.pairingKey[5]
            params.buffer[i] ^= updatedRandomSyncKey

            params.buffer[i] ^= secondLvlEncryptionLookup[Int(params.pairingKey[0])]
            params.buffer[i] &+= secondLvlEncryptionLookup[Int(params.pairingKey[1])]
            params.buffer[i] &-= secondLvlEncryptionLookup[Int(params.pairingKey[2])]
            params.buffer[i] = ((params.buffer[i] >> 4) & 0x0F) | ((params.buffer[i] & 0x0F) << 4)

            params.buffer[i] ^= secondLvlEncryptionLookup[Int(params.pairingKey[3])]
            params.buffer[i] &+= secondLvlEncryptionLookup[Int(params.pairingKey[4])]
            params.buffer[i] &-= secondLvlEncryptionLookup[Int(params.pairingKey[5])]
            params.buffer[i] = ((params.buffer[i] >> 4) & 0x0F) | ((params.buffer[i] & 0x0F) << 4)

            params.buffer[i] ^= secondLvlEncryptionLookup[Int(params.randomPairingKey[0])]
            params.buffer[i] &+= secondLvlEncryptionLookup[Int(params.randomPairingKey[1])]
            params.buffer[i] &-= secondLvlEncryptionLookup[Int(params.randomPairingKey[2])]

            updatedRandomSyncKey = params.buffer[i]
        }
    } else if params.enhancedEncryption == 2 {
        if params.buffer[0] == 0xA5, params.buffer[1] == 0xA5 {
            params.buffer[0] = 0xAA
            params.buffer[1] = 0xAA
        }

        if params.buffer[params.buffer.count - 2] == 0x5A, params.buffer[params.buffer.count - 1] == 0x5A {
            params.buffer[params.buffer.count - 2] = 0xEE
            params.buffer[params.buffer.count - 1] = 0xEE
        }

        for i in 0 ..< params.buffer.count {
            params.buffer[i] &+= params.bleRandomKeys.0
            params.buffer[i] = ((params.buffer[i] >> 4) & 0x0F) | (((params.buffer[i] & 0x0F) << 4) & 0xF0)

            params.buffer[i] &-= params.bleRandomKeys.1
            params.buffer[i] ^= params.bleRandomKeys.2
        }
    }

    return (updatedRandomSyncKey, params.buffer)
}

func encodePumpCheckCommand(deviceName: String, enhancedEncryption: UInt8) -> (data: Data, isEncryptionMode: Bool) {
    var buffer = Data(count: 19)
    buffer[0] = 0xA5 // header 1
    buffer[1] = 0xA5 // header 2
    buffer[2] = 0x0C // length
    buffer[3] = DanaPacketType.TYPE_ENCRYPTION_REQUEST
    buffer[4] = 0x00 // pump_check command

    // Device name
    for i in 0 ..< 10 {
        buffer[5 + i] = UInt8(deviceName.utf8CString[i])
    }

    let crc = generateCrc(buffer: buffer[3 ..< 15], enhancedEncryption: enhancedEncryption, isEncryptionCommand: true)
    buffer[15] = UInt8((crc >> 8) & 0xFF) // crc 1
    buffer[16] = UInt8(crc & 0xFF) // crc 2

    buffer[17] = 0x5A // footer 1
    buffer[18] = 0x5A // footer 2

    let encodedData = encodePacketSerialNumber(buffer: &buffer, deviceName: deviceName)

    return (data: encodedData, isEncryptionMode: true)
}

func encodeRequestCommand(
    operationCode: UInt8,
    deviceName: String,
    enhancedEncryption: UInt8
) -> (data: Data, isEncryptionMode: Bool) {
    var buffer = Data(count: 9)
    buffer[0] = 0xA5 // header 1
    buffer[1] = 0xA5 // header 2
    buffer[2] = 0x02 // length
    buffer[3] = DanaPacketType.TYPE_ENCRYPTION_REQUEST
    buffer[4] = operationCode

    let crc = generateCrc(buffer: buffer.subdata(in: 3 ..< 5), enhancedEncryption: enhancedEncryption, isEncryptionCommand: true)
    buffer[5] = UInt8((crc >> 8) & 0xFF) // crc 1
    buffer[6] = UInt8(crc & 0xFF) // crc 2
    buffer[7] = 0x5A // footer 1
    buffer[8] = 0x5A // footer 2

    let encodedData = encodePacketSerialNumber(buffer: &buffer, deviceName: deviceName)

    return (data: encodedData, isEncryptionMode: true)
}

func encodeTimeInformation(data: Data?, deviceName: String, enhancedEncryption: UInt8) -> (data: Data, isEncryptionMode: Bool) {
    let lengthOfData = data?.count ?? 0
    var buffer = Data(count: 9 + lengthOfData)
    buffer[0] = 0xA5 // header 1
    buffer[1] = 0xA5 // header 2
    buffer[2] = UInt8(0x02 + lengthOfData) // length
    buffer[3] = DanaPacketType.TYPE_ENCRYPTION_REQUEST
    buffer[4] = 0x01 // time information command

    if let data = data, !data.isEmpty {
        // TODO: Need to find a cleaner way to solve the constant issue
        /* Original code:
         if (enhancedEncryption === 2) {
               data[1] = 0x17 ^ 0x1a;
               data[2] = 0xd1 ^ 0xc0;
               data[3] = 0xaf ^ 0xa9;
             }
         */

        for i in 0 ..< data.count {
            if enhancedEncryption == 2, i > 0, i < 4 {
                buffer[5 + i] = timeInformationEnhancedEncryption2Lookup[i]
            } else {
                buffer[5 + i] = data[i]
            }
        }
    }

    let crc = generateCrc(
        buffer: buffer.subdata(in: 3 ..< (5 + lengthOfData)),
        enhancedEncryption: enhancedEncryption,
        isEncryptionCommand: true
    )
    buffer[5 + lengthOfData] = UInt8((crc >> 8) & 0xFF) // crc 1
    buffer[6 + lengthOfData] = UInt8(crc & 0xFF) // crc 2
    buffer[7 + lengthOfData] = 0x5A // footer 1
    buffer[8 + lengthOfData] = 0x5A // footer 2

    let encodedData = encodePacketSerialNumber(buffer: &buffer, deviceName: deviceName)

    return (data: encodedData, isEncryptionMode: true)
}

func encodeCheckPassKeyCommand(
    data: Data?,
    deviceName: String,
    enhancedEncryption: UInt8
) -> (data: Data, isEncryptionMode: Bool) {
    let lengthOfData = data?.count ?? 0
    var buffer = Data(count: 9 + lengthOfData)
    buffer[0] = 0xA5 // header 1
    buffer[1] = 0xA5 // header 2
    buffer[2] = UInt8(0x02 + lengthOfData) // length
    buffer[3] = DanaPacketType.TYPE_ENCRYPTION_REQUEST
    buffer[4] = 0xD0 // check passkey command

    if let data = data, !data.isEmpty {
        for i in 0 ..< data.count {
            buffer[5 + i] = encodePacketPassKeySerialNumber(value: data[i], deviceName: deviceName)
        }
    }

    let crc = generateCrc(
        buffer: buffer.subdata(in: 3 ..< (5 + lengthOfData)),
        enhancedEncryption: enhancedEncryption,
        isEncryptionCommand: true
    )
    buffer[5 + lengthOfData] = UInt8((crc >> 8) & 0xFF) // crc 1
    buffer[6 + lengthOfData] = UInt8(crc & 0xFF) // crc 2
    buffer[7 + lengthOfData] = 0x5A // footer 1
    buffer[8 + lengthOfData] = 0x5A // footer 2

    let encodedData = encodePacketSerialNumber(buffer: &buffer, deviceName: deviceName)
    return (data: encodedData, isEncryptionMode: true)
}

func encodeDefault(options: EncryptParams) -> (data: Data, isEncryptionMode: Bool) {
    let lengthOfData = options.data?.count ?? 0
    var buffer = Data(count: 9 + lengthOfData)
    buffer[0] = 0xA5 // header 1
    buffer[1] = 0xA5 // header 2
    buffer[2] = UInt8(0x02 + lengthOfData) // length
    buffer[3] = DanaPacketType.TYPE_COMMAND
    buffer[4] = options.operationCode // operation code

    if let data = options.data, lengthOfData > 0 {
        for i in 0 ..< lengthOfData {
            buffer[5 + i] = data[i]
        }
    }

    let crc = generateCrc(
        buffer: buffer.subdata(in: 3 ..< (5 + lengthOfData)),
        enhancedEncryption: options.enhancedEncryption,
        isEncryptionCommand: false
    )
    buffer[5 + lengthOfData] = UInt8((crc >> 8) & 0xFF) // crc 1
    buffer[6 + lengthOfData] = UInt8(crc & 0xFF) // crc 2
    buffer[7 + lengthOfData] = 0x5A // footer 1
    buffer[8 + lengthOfData] = 0x5A // footer 2

    var encrypted1 = encodePacketSerialNumber(buffer: &buffer, deviceName: options.deviceName)
    if options.enhancedEncryption == 0 {
        encrypted1 = encodePacketTime(buffer: &encrypted1, timeSecret: options.timeSecret)
        encrypted1 = encodePacketPassword(buffer: &encrypted1, passwordSecret: options.passwordSecret)
        encrypted1 = encodePacketPassKey(buffer: &encrypted1, passkeySecret: options.passKeySecret)
    }

    return (data: encrypted1, isEncryptionMode: false)
}
