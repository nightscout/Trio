//
//  RFPacket.swift
//  RileyLinkBLEKit
//
//  Created by Pete Schwamb on 9/16/17.
//  Copyright © 2017 Pete Schwamb. All rights reserved.
//

import Foundation

public struct RFPacket : CustomStringConvertible {
    public let data: Data
    let packetCounter: Int
    public let rssi: Int

    public init?(rfspyResponse: Data) {
        guard rfspyResponse.count >= 2 else {
            return nil
        }

        let startIndex = rfspyResponse.startIndex
        
        let rssiDec = Int(rfspyResponse[startIndex])
        let rssiOffset = 73
        if rssiDec >= 128 {
            self.rssi = (rssiDec - 256) / 2 - rssiOffset
        } else {
            self.rssi = rssiDec / 2 - rssiOffset
        }

        self.packetCounter = Int(rfspyResponse[startIndex.advanced(by: 1)])
        
        self.data = rfspyResponse.subdata(in: startIndex.advanced(by: 2)..<rfspyResponse.endIndex)
    }

    public var description: String {
        return String(format: "RFPacket(%1$@, %2$@, %3$@)", String(describing: rssi), String(describing: packetCounter), data.hexadecimalString)
    }

}

