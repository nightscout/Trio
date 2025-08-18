struct DecryptParam {
    var data: Data
    var deviceName: String
    var enhancedEncryption: UInt8
    var isEncryptionMode: Bool
    var pairingKeyLength: Int
    var randomPairingKeyLength: Int
    var ble5KeyLength: Int
    var timeSecret: Data
    var passwordSecret: Data
    var passKeySecret: Data
    var passKeySecretBackup: Data
}

struct DecryptReturn {
    var data: Data
    var isEncryptionMode: Bool
    var timeSecret: Data
    var passwordSecret: Data
    var passKeySecret: Data
    var passKeySecretBackup: Data
}

func decrypt(_ options: inout DecryptParam) throws -> DecryptReturn {
    options.data = encodePacketSerialNumber(buffer: &options.data, deviceName: options.deviceName)

    if !options.isEncryptionMode, options.enhancedEncryption == 0 {
        options.data = encodePacketTime(buffer: &options.data, timeSecret: options.timeSecret)
        options.data = encodePacketPassword(buffer: &options.data, passwordSecret: options.passwordSecret)
        options.data = encodePacketPassKey(buffer: &options.data, passkeySecret: options.passKeySecret)
    }

    guard options.data[2] == options.data.count - 7 else {
        throw NSError(domain: "Package length does not match the length attr.", code: 0, userInfo: nil)
    }

    var content = Data(options.data[3 ... (options.data.count - 5)])
    let crc = generateCrc(
        buffer: content,
        enhancedEncryption: options.enhancedEncryption,
        isEncryptionCommand: options.isEncryptionMode
    )

    guard (UInt16(crc) >> 8) == options.data[options.data.count - 4],
          (UInt16(crc) & 0xFF) == options.data[options.data.count - 3]
    else {
        throw NSError(domain: "Crc checksum failed...", code: 0, userInfo: nil)
    }

    if content[0] == 0x2, content[1] == 0xD0, content[2] == 0x0 {
        // Response for DANAR_PACKET__OPCODE_ENCRYPTION__CHECK_PASSKEY
        options.passKeySecret = options.passKeySecretBackup
    }

    if content[0] == 0x2, content[1] == 0xD2 {
        // Response for ??
        options.passKeySecret = Data([content[2], content[3]])
        options.passKeySecretBackup = Data([content[2], content[3]])

        content[2] = encodePacketPassKeySerialNumber(value: content[2], deviceName: options.deviceName)
        content[3] = encodePacketPassKeySerialNumber(value: content[3], deviceName: options.deviceName)
    }

    if content[0] == 0x2, content[1] == 0x1 {
        // Response for DANAR_PACKET__OPCODE_ENCRYPTION__TIME_INFORMATION
        if options.enhancedEncryption == 1 {
            options.isEncryptionMode = options.pairingKeyLength == 0 && options.randomPairingKeyLength == 0
        } else if options.enhancedEncryption == 2 {
            options.isEncryptionMode = options.ble5KeyLength == 0
        } else {
            // The initial message
            if options.data.count != 0x11 {
                throw NSError(domain: "Invalid length for TIME_INFORMATION", code: 0, userInfo: nil)
            }

            options.isEncryptionMode = false
            options.timeSecret = Data(content[2 ... 7])

            options.passwordSecret = Data(content[8 ... 9])
            options.passwordSecret[0] ^= 0x87
            options.passwordSecret[1] ^= 0x0D
        }
    }

    return DecryptReturn(
        data: content,
        isEncryptionMode: options.isEncryptionMode,
        timeSecret: options.timeSecret,
        passwordSecret: options.passwordSecret,
        passKeySecret: options.passKeySecret,
        passKeySecretBackup: options.passKeySecretBackup
    )
}

struct DecryptSecondLevelParams {
    var buffer: Data
    var enhancedEncryption: UInt8
    var pairingKey: Data
    var randomPairingKey: Data
    var randomSyncKey: UInt8
    var bleRandomKeys: (UInt8, UInt8, UInt8)
}

func decryptSecondLevel(_ params: inout DecryptSecondLevelParams) -> (randomSyncKey: UInt8, buffer: Data) {
    if params.enhancedEncryption == 1 {
        for i in 0 ..< params.buffer.count {
            let copyRandomSyncKey = params.buffer[i]

            params.buffer[i] &+= secondLvlEncryptionLookup[Int(params.randomPairingKey[2])]
            params.buffer[i] &-= secondLvlEncryptionLookup[Int(params.randomPairingKey[1])]
            params.buffer[i] ^= secondLvlEncryptionLookup[Int(params.randomPairingKey[0])]
            params.buffer[i] = ((params.buffer[i] >> 4) & 0xF) | (((params.buffer[i] & 0xF) << 4) & 0xFF)

            params.buffer[i] &+= secondLvlEncryptionLookup[Int(params.pairingKey[5])]
            params.buffer[i] &-= secondLvlEncryptionLookup[Int(params.pairingKey[4])]
            params.buffer[i] ^= secondLvlEncryptionLookup[Int(params.pairingKey[3])]
            params.buffer[i] = ((params.buffer[i] >> 4) & 0xF) | (((params.buffer[i] & 0xF) << 4) & 0xFF)

            params.buffer[i] &+= secondLvlEncryptionLookup[Int(params.pairingKey[2])]
            params.buffer[i] &-= secondLvlEncryptionLookup[Int(params.pairingKey[1])]
            params.buffer[i] ^= secondLvlEncryptionLookup[Int(params.pairingKey[0])]
            params.buffer[i] ^= params.randomSyncKey
            params.buffer[i] ^= params.pairingKey[5]

            params.buffer[i] = ((params.buffer[i] >> 4) & 0xF) | (((params.buffer[i] & 0xF) << 4) & 0xFF)
            params.buffer[i] ^= params.pairingKey[4]
            params.buffer[i] &+= params.pairingKey[3]

            params.buffer[i] = ((params.buffer[i] >> 4) & 0xF) | (((params.buffer[i] & 0xF) << 4) & 0xFF)
            params.buffer[i] ^= params.pairingKey[2]
            params.buffer[i] &-= params.pairingKey[1]

            params.buffer[i] = ((params.buffer[i] >> 4) & 0xF) | (((params.buffer[i] & 0xF) << 4) & 0xFF)
            params.buffer[i] &+= params.randomSyncKey
            params.buffer[i] ^= params.pairingKey[0]

            params.randomSyncKey = copyRandomSyncKey
        }

        if params.buffer[0] == 0x7A, params.buffer[1] == 0x7A {
            params.buffer[0] = 0xA5
            params.buffer[1] = 0xA5
        }

        if params.buffer[params.buffer.count - 2] == 0x2E, params.buffer[params.buffer.count - 1] == 0x2E {
            params.buffer[params.buffer.count - 2] = 0x5A
            params.buffer[params.buffer.count - 1] = 0x5A
        }
    } else if params.enhancedEncryption == 2 {
        for i in 0 ..< params.buffer.count {
            params.buffer[i] ^= params.bleRandomKeys.2
            params.buffer[i] &+= params.bleRandomKeys.1

            params.buffer[i] = ((params.buffer[i] >> 4) & 0xF) | (((params.buffer[i] & 0xF) << 4) & 0xFF)
            params.buffer[i] &-= params.bleRandomKeys.0
        }
    }

    return (params.randomSyncKey, params.buffer)
}
