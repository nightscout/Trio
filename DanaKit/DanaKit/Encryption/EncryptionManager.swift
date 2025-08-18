enum DanaRSEncryption {
    public private(set) static var enhancedEncryption: UInt8 = 0
    private static var isEncryptionMode: Bool = true

    // Length 2
    private static var passwordSecret = Data()

    // Length: 6
    private static var timeSecret = Data()

    // Length: 2
    private static var passKeySecret = Data()
    private static var passKeySecretBackup = Data()

    // Length: 6
    private static var pairingKey = Data()

    // Length: 3
    private static var randomPairingKey = Data()
    public private(set) static var randomSyncKey: UInt8 = 0

    // Length: 6
    private static var ble5Key = Data()
    private static var ble5RandomKeys: (UInt8, UInt8, UInt8) = (0, 0, 0)

    // Encoding functions -> Encryption in JNI lib
    static func encodePacket(operationCode: UInt8, buffer: Data?, deviceName: String) -> Data {
        let params = EncryptParams(
            operationCode: operationCode,
            data: buffer,
            deviceName: deviceName,
            enhancedEncryption: enhancedEncryption,
            timeSecret: timeSecret,
            passwordSecret: passwordSecret,
            passKeySecret: passKeySecret
        )
        let result = encrypt(params)

        isEncryptionMode = result.isEncryptionMode
        return result.data
    }

    static func encodeSecondLevel(data: Data) -> Data {
        var params = EncryptSecondLevelParams(
            buffer: data,
            enhancedEncryption: enhancedEncryption,
            pairingKey: pairingKey,
            randomPairingKey: randomPairingKey,
            randomSyncKey: randomSyncKey,
            bleRandomKeys: ble5RandomKeys
        )
        let result = encryptSecondLevel(&params)

        randomSyncKey = result.randomSyncKey
        return result.buffer
    }

    // Decoding function -> Decrypting in JNI lib
    static func decodePacket(buffer: Data, deviceName: String) -> Data {
        var params = DecryptParam(
            data: buffer,
            deviceName: deviceName,
            enhancedEncryption: enhancedEncryption,
            isEncryptionMode: isEncryptionMode,
            pairingKeyLength: pairingKey.count,
            randomPairingKeyLength: randomPairingKey.count,
            ble5KeyLength: ble5Key.count,
            timeSecret: timeSecret,
            passwordSecret: passwordSecret,
            passKeySecret: passKeySecret,
            passKeySecretBackup: passKeySecretBackup
        )

        do {
            let decryptionResult = try decrypt(&params)

            isEncryptionMode = decryptionResult.isEncryptionMode
            timeSecret = decryptionResult.timeSecret
            passwordSecret = decryptionResult.passwordSecret
            passKeySecret = decryptionResult.passKeySecret
            passKeySecretBackup = decryptionResult.passKeySecretBackup

            return decryptionResult.data
        } catch {
            return Data([])
        }
    }

    static func decodeSecondLevel(data: Data) -> Data {
        var params = DecryptSecondLevelParams(
            buffer: data,
            enhancedEncryption: enhancedEncryption,
            pairingKey: pairingKey,
            randomPairingKey: randomPairingKey,
            randomSyncKey: randomSyncKey,
            bleRandomKeys: ble5RandomKeys
        )
        let result = decryptSecondLevel(&params)

        randomSyncKey = result.randomSyncKey
        return result.buffer
    }

    // Setter functions
    static func setEnhancedEncryption(_ enhancedEncryption: UInt8) {
        self.enhancedEncryption = enhancedEncryption
    }

    static func setPairingKeys(pairingKey: Data, randomPairingKey: Data, randomSyncKey: UInt8?) {
        self.pairingKey = pairingKey
        self.randomPairingKey = randomPairingKey

        if randomSyncKey == nil || randomSyncKey == 0 {
            self.randomSyncKey = initialRandomSyncKey(pairingKey: pairingKey)
        } else {
            self.randomSyncKey = decryptionRandomSyncKey(randomSyncKey: randomSyncKey!, randomPairingKey: randomPairingKey)
        }
    }

    static func getPairingKeys() -> (Data, Data) {
        return (pairingKey, randomPairingKey)
    }

    static func setBle5Key(ble5Key: Data) {
        self.ble5Key = ble5Key

        let i1 = Int((ble5Key[0] - 0x30) * 10) &+ Int(ble5Key[1] - 0x30)
        let i2 = Int((ble5Key[2] - 0x30) * 10) &+ Int(ble5Key[3] - 0x30)
        let i3 = Int((ble5Key[4] - 0x30) * 10) &+ Int(ble5Key[5] - 0x30)

        ble5RandomKeys = (
            secondLvlEncryptionLookupShort[Int(i1)],
            secondLvlEncryptionLookupShort[Int(i2)],
            secondLvlEncryptionLookupShort[Int(i3)]
        )
    }
}
