//
//  BLEFirmwareVersion.swift
//  RileyLinkBLEKit
//
//  Copyright © 2017 Pete Schwamb. All rights reserved.
//

public struct BLEFirmwareVersion {
    private static let prefix = "ble_rfspy "

    let components: [Int]

    let versionString: String

    init?(versionString: String) {
        guard
            versionString.hasPrefix(BLEFirmwareVersion.prefix),
            let versionIndex = versionString.index(versionString.startIndex, offsetBy: BLEFirmwareVersion.prefix.count, limitedBy: versionString.endIndex)
        else {
            return nil
        }

        self.init(
            components: versionString[versionIndex...].split(separator: ".").compactMap({ Int($0) }),
            versionString: versionString
        )
    }

    init(components: [Int], versionString: String) {
        self.components = components
        self.versionString = versionString
    }
}


extension BLEFirmwareVersion {
    static var unknown: BLEFirmwareVersion {
        return self.init(components: [0], versionString: "Unknown")
    }

    public var isUnknown: Bool {
        return self == BLEFirmwareVersion.unknown
    }
}


extension BLEFirmwareVersion: CustomStringConvertible {
    public var description: String {
        return versionString
    }
}


extension BLEFirmwareVersion: Equatable {
    public static func ==(lhs: BLEFirmwareVersion, rhs: BLEFirmwareVersion) -> Bool {
        return lhs.components == rhs.components
    }
}


extension BLEFirmwareVersion {
    var responseType: PeripheralManager.ResponseType {
        guard let major = components.first, major >= 2 else {
            return .buffered
        }

        return .single
    }
}
