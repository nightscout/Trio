//
//  MiaoMiao.swift
//  LibreMonitor
//
//  Created by Uwe Petersen on 02.11.18.
//  Copyright © 2018 Uwe Petersen. All rights reserved.
//

import Foundation

public struct LibreTransmitterMetadata: CustomStringConvertible {
    // hardware number
    public let hardware: String?
    // software number
    public let firmware: String?
    // battery level, percentage between 0 % and 100 %
    public let battery: Int?
    // battery level String
    public let batteryString: String

    public let macAddress: String?

    public let name: String

    public let patchInfo: Data?
    public let uid: [UInt8]?

    init(hardware: String?, firmware: String?, battery: Int?, name: String, macAddress: String?, patchInfo: Data?, uid: [UInt8]?) {
        self.hardware = hardware
        self.firmware = firmware
        self.battery = battery
        let batteryString = battery == nil ? "-" : "\(battery!)"
        self.batteryString = batteryString
        self.macAddress = macAddress
        self.name = name
        self.patchInfo = patchInfo
        self.uid = uid
    }

    public var description: String {
        "Transmitter: \(name), Hardware: \(String(describing: hardware)), firmware: \(String(describing: firmware))" +
        "battery: \(batteryString), macAddress: \(String(describing: macAddress)), patchInfo: \(String(describing: patchInfo)), uid: \(String(describing: uid))"
    }

    public func sensorType() -> SensorType? {
        guard let patchInfo else { return nil }
        return SensorType(patchInfo: patchInfo)
    }
}

extension String {
    // https://stackoverflow.com/questions/39677330/how-does-string-substring-work-in-swift
    // usage
    // let s = "hello"
    // s[0..<3] // "hel"
    // s[3..<s.count] // "lo"
    subscript(_ range: CountableRange<Int>) -> String {
        let idx1 = index(startIndex, offsetBy: max(0, range.lowerBound))
        let idx2 = index(startIndex, offsetBy: min(self.count, range.upperBound))
        return String(self[idx1..<idx2])
    }

    func hexadecimal() -> Data? {
        var data = Data(capacity: count / 2)
        // swiftlint:disable:next force_try
        let regex = try! NSRegularExpression(pattern: "[0-9a-f]{1,2}", options: .caseInsensitive)
        regex.enumerateMatches(in: self, range: NSRange(startIndex..., in: self)) { match, _, _ in
            let byteString = (self as NSString).substring(with: match!.range)
            let num = UInt8(byteString, radix: 16)!
            data.append(num)
        }

        guard data.count > 0 else { return nil }

        return data
    }
}

public enum SensorFamily: Int, CustomStringConvertible {
    case libre      = 0
    case librePro   = 1
    case libre2     = 3
    case libreSense = 7

    public var description: String {
        switch self {
        case .libre:      return "Libre"
        case .librePro:   return "Libre Pro"
        case .libre2:     return "Libre 2"
        case .libreSense: return "Libre Sense"
        }
    }
}

public enum SensorType: String, CustomStringConvertible {
    case libre1       = "Libre 1"
    case libreUS14day = "Libre US 14d"
    case libreProH    = "Libre Pro/H"
    case libre2       = "Libre 2"
    case libre2US     = "Libre 2 US"
    case libre2CA     = "Libre 2 CA"
    case libreSense   = "Libre Sense"
    case libre3       = "Libre 3"
    case dexcomOne    = "Dexcom ONE"
    case dexcomG7     = "Dexcom G7"
    case unknown      = "Libre"

    public init(patchInfo: Data) {
        switch patchInfo[0] {
        case 0xDF, 0xA2: self = .libre1
        case 0xE5, 0xE6: self = .libreUS14day
        case 0x70: self = .libreProH
        case 0xC5, 0x9D: self = .libre2
        case 0x76: self = patchInfo[3] == 0x02 ? .libre2US : patchInfo[3] == 0x04 ? .libre2CA : patchInfo[2] >> 4 == 7 ? .libreSense : .unknown
        default:
            if patchInfo.count == 24 {
                self = .libre3
            } else {
                self = .unknown
            }
        }
    }

    public var description: String { self.rawValue }
}
