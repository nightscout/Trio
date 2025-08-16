// exec_get_enc_packet_passkey(char*, Int, char*)
func encodePacketPassKey(buffer: inout Data, passkeySecret: Data) -> Data {
    guard !passkeySecret.isEmpty else {
        return buffer
    }

    for i in 0 ..< (buffer.count - 5) {
        buffer[i + 3] ^= passkeySecret[(i + 1) % 2]
    }

    return buffer
}

// exec_get_enc_passkey_sn(byte, char*)
func encodePacketPassKeySerialNumber(value: UInt8, deviceName: String) -> UInt8 {
    var tmp: UInt8 = 0
    for i in 0 ..< min(10, deviceName.count) {
        let charCode = UInt8(deviceName.utf8CString[i])
        tmp = tmp &+ charCode
    }

    return value ^ tmp
}

// exec_get_enc_packet_password
func encodePacketPassword(buffer: inout Data, passwordSecret: Data) -> Data {
    guard passwordSecret.count == 2 else {
        return buffer
    }

    let tmp = passwordSecret[0] &+ passwordSecret[1]
    for i in 3 ..< (buffer.count - 2) {
        buffer[i] ^= tmp
    }

    return buffer
}

// exec_get_enc_packet_sn(char*, Int, char*)
func encodePacketSerialNumber(buffer: inout Data, deviceName: String) -> Data {
    let tmp = Data([
        UInt8(deviceName.utf8CString[0]) &+ UInt8(deviceName.utf8CString[1]) &+ UInt8(deviceName.utf8CString[2]),
        UInt8(deviceName.utf8CString[3]) &+ UInt8(deviceName.utf8CString[4]) &+ UInt8(deviceName.utf8CString[5]) &+
            UInt8(deviceName.utf8CString[6]) &+ UInt8(deviceName.utf8CString[7]),
        UInt8(deviceName.utf8CString[8]) &+ UInt8(deviceName.utf8CString[9])
    ])

    for i in 0 ..< (buffer.count - 5) {
        buffer[i + 3] ^= tmp[i % 3]
    }

    return buffer
}

// exec_get_enc_packet_time(char*, Int, char*)
func encodePacketTime(buffer: inout Data, timeSecret: Data) -> Data {
    let tmp = timeSecret.reduce(0, +)
    for i in 3 ..< (buffer.count - 2) {
        buffer[i] ^= tmp
    }

    return buffer
}

// exec_get_enc_pairingkey(int, int)
func encodePairingKey(
    buffer: inout Data,
    pairingKey: Data,
    globalRandomSyncKey: UInt8
) -> (globalRandomSyncKey: UInt8, buffer: Data) {
    var newRandomSyncKey = globalRandomSyncKey

    for i in 0 ..< buffer.count {
        buffer[i] ^= pairingKey[0]
        buffer[i] &-= newRandomSyncKey
        buffer[i] = ((buffer[i] >> 4) & 0xF) | ((buffer[i] & 0xF) << 4)

        buffer[i] &+= pairingKey[1]
        buffer[i] ^= pairingKey[2]
        buffer[i] = ((buffer[i] >> 4) & 0xF) | ((buffer[i] & 0xF) << 4)

        buffer[i] &-= pairingKey[3]
        buffer[i] ^= pairingKey[4]
        buffer[i] = ((buffer[i] >> 4) & 0xF) | ((buffer[i] & 0xF) << 4)

        buffer[i] ^= pairingKey[5]
        buffer[i] ^= newRandomSyncKey

        newRandomSyncKey = buffer[i]
    }

    // set global random sync key to newRandomSyncKey
    return (globalRandomSyncKey: newRandomSyncKey, buffer: buffer)
}

// exec_get_desc_pairingkey(char*, int)
func getDescPairingKey(
    buffer: inout Data,
    pairingKey: Data,
    globalRandomSyncKey: UInt8
) -> (globalRandomSyncKey: UInt8, buffer: Data) {
    // This is the reverse of encodePairingKey
    var newRandomSyncKey = globalRandomSyncKey

    for i in 0 ..< buffer.count {
        let tmp = buffer[i]

        buffer[i] ^= newRandomSyncKey
        buffer[i] ^= pairingKey[5]

        buffer[i] = ((buffer[i] >> 4) & 0xF) | ((buffer[i] & 0xF) << 4)
        buffer[i] ^= pairingKey[4]
        buffer[i] &-= pairingKey[3]

        buffer[i] = ((buffer[i] >> 4) & 0xF) | ((buffer[i] & 0xF) << 4)
        buffer[i] ^= pairingKey[2]
        buffer[i] &+= pairingKey[1]
        buffer[i] ^= pairingKey[0]

        buffer[i] = ((buffer[i] >> 4) & 0xF) | ((buffer[i] & 0xF) << 4)
        buffer[i] &-= newRandomSyncKey

        // set global random sync key to newRandomSyncKey
        newRandomSyncKey = tmp
    }

    return (globalRandomSyncKey: newRandomSyncKey, buffer: buffer)
}

func encryptionRandomSyncKey(randomSyncKey: UInt8, randomPairingKey: Data) -> UInt8 {
    var tmp: UInt8 = 0

    tmp = ((randomSyncKey >> 4) | ((randomSyncKey & 0xF) << 4)) &+ randomPairingKey[0]
    tmp = ((tmp >> 4) | ((tmp & 0xF) << 4)) ^ randomPairingKey[1]

    return ((tmp >> 4) | ((tmp & 0xF) << 4)) &- randomPairingKey[2]
}

func decryptionRandomSyncKey(randomSyncKey: UInt8, randomPairingKey: Data) -> UInt8 {
    var tmp: UInt8 = 0

    tmp = (((randomSyncKey &+ randomPairingKey[2]) >> 4) | ((randomSyncKey &+ randomPairingKey[2]) & 0xF) << 4) ^
        randomPairingKey[1]
    tmp = ((tmp >> 4) | ((tmp & 0xF) << 4)) &- randomPairingKey[0]

    return (tmp >> 4) | ((tmp & 0xF) << 4)
}

func initialRandomSyncKey(pairingKey: Data) -> UInt8 {
    var tmp: UInt8 = 0

    tmp = (((pairingKey[0] &+ pairingKey[1]) >> 4) | (((pairingKey[0] &+ pairingKey[1]) & 0xF) << 4) ^ pairingKey[2]) &-
        pairingKey[3]
    tmp = ((tmp >> 4) | ((tmp & 0xF) << 4)) ^ pairingKey[4]

    return ((tmp >> 4) | ((tmp & 0xF) << 4)) ^ pairingKey[5]
}
