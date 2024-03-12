//
//  CRC.swift
//  LibreMonitor
//
//  Created by Uwe Petersen on 26.07.16.
//  Copyright © 2016 Uwe Petersen. All rights reserved.
//
//
//  Part of this code is taken from
//  CRC.swift
//  CryptoSwift
//
//  Created by Marcin Krzyzanowski on 25/08/14.
//  Copyright (c) 2014 Marcin Krzyzanowski. All rights reserved.
//

import Foundation

final class Crc {
    /// Table of precalculated crc16 values
    // swiftlint:disable:next line_length
    static let crc16table: [UInt16] = [0, 4_489, 8_978, 12_955, 17_956, 22_445, 25_910, 29_887, 35_912, 40_385, 44_890, 48_851, 51_820, 56_293, 59_774, 63_735, 4_225, 264, 13_203, 8_730, 22_181, 18_220, 30_135, 25_662, 40_137, 36_160, 49_115, 44_626, 56_045, 52_068, 63_999, 59_510, 8_450, 12_427, 528, 5_017, 26_406, 30_383, 17_460, 21_949, 44_362, 48_323, 36_440, 40_913, 60_270, 64_231, 51_324, 55_797, 12_675, 8_202, 4_753, 792, 30_631, 26_158, 21_685, 17_724, 48_587, 44_098, 40_665, 36_688, 64_495, 60_006, 55_549, 51_572, 16_900, 21_389, 24_854, 28_831, 1_056, 5_545, 10_034, 14_011, 52_812, 57_285, 60_766, 64_727, 34_920, 39_393, 43_898, 47_859, 21_125, 17_164, 29_079, 24_606, 5_281, 1_320, 14_259, 9_786, 57_037, 53_060, 64_991, 60_502, 39_145, 35_168, 48_123, 43_634, 25_350, 29_327, 16_404, 20_893, 9_506, 13_483, 1_584, 6_073, 61_262, 65_223, 52_316, 56_789, 43_370, 47_331, 35_448, 39_921, 29_575, 25_102, 20_629, 16_668, 13_731, 9_258, 5_809, 1_848, 65_487, 60_998, 56_541, 52_564, 47_595, 43_106, 39_673, 35_696, 33_800, 38_273, 42_778, 46_739, 49_708, 54_181, 57_662, 61_623, 2_112, 6_601, 11_090, 15_067, 20_068, 24_557, 28_022, 31_999, 38_025, 34_048, 47_003, 42_514, 53_933, 49_956, 61_887, 57_398, 6_337, 2_376, 15_315, 10_842, 24_293, 20_332, 32_247, 27_774, 42_250, 46_211, 34_328, 38_801, 58_158, 62_119, 49_212, 53_685, 10_562, 14_539, 2_640, 7_129, 28_518, 32_495, 19_572, 24_061, 46_475, 41_986, 38_553, 34_576, 62_383, 57_894, 53_437, 49_460, 14_787, 10_314, 6_865, 2_904, 32_743, 28_270, 23_797, 19_836, 50_700, 55_173, 58_654, 62_615, 32_808, 37_281, 41_786, 45_747, 19_012, 23_501, 26_966, 30_943, 3_168, 7_657, 12_146, 16_123, 54_925, 50_948, 62_879, 58_390, 37_033, 33_056, 46_011, 41_522, 23_237, 19_276, 31_191, 26_718, 7_393, 3_432, 16_371, 11_898, 59_150, 63_111, 50_204, 54_677, 41_258, 45_219, 33_336, 37_809, 27_462, 31_439, 18_516, 23_005, 11_618, 15_595, 3_696, 8_185, 63_375, 58_886, 54_429, 50_452, 45_483, 40_994, 37_561, 33_584, 31_687, 27_214, 22_741, 18_780, 15_843, 11_370, 7_921, 3_960]

    /// Calculates crc16. Taken from https://github.com/krzyzanowskim/CryptoSwift with modifications (reversing and byte swapping) to adjust for crc as used by Freestyle Libre
    ///
    /// - parameter message: Array of bytes for which the crc is to be calculated
    /// - parameter seed:    seed for crc
    ///
    /// - returns: crc16
    static func crc16(_ message: [UInt8], seed: UInt16? = nil) -> UInt16 {
        var crc: UInt16 = seed != nil ? seed! : 0x0000

        // calculate crc
        for chunk in BytesSequence(chunkSize: 256, data: message) {
            for b in chunk {
                crc = (crc >> 8) ^ crc16table[Int((crc ^ UInt16(b)) & 0xFF)]
            }
        }

        // reverse the bits (modification by Uwe Petersen, 2016-06-05)
        var reverseCrc = UInt16(0)
        for _ in 0..<16 {
            reverseCrc = reverseCrc << 1 | crc & 1
            crc >>= 1
        }

        // swap bytes and return (modification by Uwe Petersen, 2016-06-05)
        return reverseCrc.byteSwapped
    }

    /// Checks crc for an array of bytes.
    ///
    /// Assumes that the first two bytes are the crc16 of the bytes array and compares the corresponding value with the crc16 calculated over the rest of the array of bytes.
    ///
    /// - parameter bytes: Array of bytes with a crc in the first two bytes
    ///
    /// - returns: true if crc is valid
    static func hasValidCrc16InFirstTwoBytes(_ bytes: [UInt8]) -> Bool {
//        print(Array(bytes.dropFirst(2)))
        let calculatedCrc = Crc.crc16(Array(bytes.dropFirst(2)), seed: 0xffff)
        let enclosedCrc = (UInt16(bytes[0]) << 8) | UInt16(bytes[1])

//        print(String(format: "Calculated crc is %X and enclosed crc is %x", arguments: [calculatedCrc, enclosedCrc]))

        return calculatedCrc == enclosedCrc
    }

    static func hasValidCrc16InLastTwoBytes(_ bytes: [UInt8]) -> Bool {
        let calculatedCrc = Crc.crc16(Array(bytes.dropLast(2)), seed: 0xffff)
        let enclosedCrc = (UInt16(Array(bytes.suffix(2))[0]) << 8) | UInt16(Array(bytes.suffix(2))[1])

        return calculatedCrc == enclosedCrc
    }

    /// Returns a byte array with correct crc in first two bytes (calculated over the remaining bytes).
    ///
    /// In case some bytes of the original byte array are tweaked, the original crc does not match the remainaing bytes any more. This function calculates the correct crc of the bytes from byte #0x02 to the end and replaces the first two bytes with the correct crc.
    ///
    /// - Parameter bytes: byte array
    /// - Returns: byte array with correct crc in first two bytes
    static func bytesWithCorrectCRC(_ bytes: [UInt8]) -> [UInt8] {
        let calculatedCrc = Crc.crc16(Array(bytes.dropFirst(2)), seed: 0xffff)

        var correctedBytes = bytes
        correctedBytes[0] = UInt8(calculatedCrc >> 8)
        correctedBytes[1] = UInt8(calculatedCrc & 0x00FF)
        return correctedBytes
    }
}

/// Struct BytesSequence, taken from https://github.com/krzyzanowskim/CryptoSwift
struct BytesSequence: Sequence {
    let chunkSize: Int
    let data: [UInt8]

    func makeIterator() -> AnyIterator<ArraySlice<UInt8>> {
        var offset: Int = 0

        return AnyIterator {
            let end = Swift.min(self.chunkSize, self.data.count - offset)
            let result = self.data[offset..<offset + end]
            offset += result.count
            return !result.isEmpty ? result : nil
        }
    }
}
