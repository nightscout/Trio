//
//  RadioFirmwareVersion.swift
//  RileyLinkBLEKit
//
//  Copyright © 2017 Pete Schwamb. All rights reserved.
//

public struct RadioFirmwareVersion {
    private static let prefix = "subg_rfspy "

    let components: [Int]

    let versionString: String

    init?(versionString: String) {
        guard versionString.hasPrefix(RadioFirmwareVersion.prefix),
            let versionIndex = versionString.index(versionString.startIndex, offsetBy: RadioFirmwareVersion.prefix.count, limitedBy: versionString.endIndex)
        else {
            return nil
        }

        self.init(
            components: versionString[versionIndex...].split(separator: ".").compactMap({ Int($0) }),
            versionString: versionString
        )
    }

    private init(components: [Int], versionString: String) {
        self.versionString = versionString
        self.components = components
    }
}


extension RadioFirmwareVersion {
    static var unknown: RadioFirmwareVersion {
        return self.init(components: [0], versionString: "Unknown")
    }

    public var isUnknown: Bool {
        return self == RadioFirmwareVersion.unknown
    }
}


extension RadioFirmwareVersion: CustomStringConvertible {
    public var description: String {
        return versionString
    }
}

extension RadioFirmwareVersion: Equatable {
    public static func ==(lhs: RadioFirmwareVersion, rhs: RadioFirmwareVersion) -> Bool {
        return lhs.components == rhs.components
    }
}

// Version 2 changes
extension RadioFirmwareVersion {
    
    private var atLeastV2: Bool {
        guard let major = components.first, major >= 2 else {
            return false
        }
        return true
    }
    
    private var atLeastV2_2: Bool {
        guard components.count >= 2 else {
            return false;
        }
        let major = components[0]
        let minor = components[1]
        return major > 2 || (major == 2 && minor >= 2)
    }

    
    var supportsPreambleExtension: Bool {
        return atLeastV2
    }
    
    var supportsSoftwareEncoding: Bool {
        return atLeastV2
    }
    
    var supportsResetRadioConfig: Bool {
        return atLeastV2
    }

    var supports16BitPacketDelay: Bool {
        return atLeastV2
    }
    
    var needsExtraByteForUpdateRegisterCommand: Bool {
        // Fixed in 2.2
        return !atLeastV2
    }

    var needsExtraByteForReadRegisterCommand: Bool {
        // Fixed in 2.3
        guard components.count >= 2 else {
            return true;
        }
        let major = components[0]
        let minor = components[1]
        return major < 2 || (major == 2 && minor <= 2)
    }

    var supportsRileyLinkStatistics: Bool {
        return atLeastV2_2
    }

    var supportsCustomPreamble: Bool {
        return atLeastV2
    }
    
    var supportsReadRegister: Bool {
        return atLeastV2
    }

}

