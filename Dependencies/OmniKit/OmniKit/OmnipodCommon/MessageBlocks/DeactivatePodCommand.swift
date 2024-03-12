//
//  DeactivatePodCommand.swift
//  OmniKit
//
//  Created by Pete Schwamb on 2/24/18.
//  Copyright © 2018 Pete Schwamb. All rights reserved.
//

import Foundation

public struct DeactivatePodCommand : NonceResyncableMessageBlock {
    
    // ID1:1f00ee84 PTYPE:PDM SEQ:09 ID2:1f00ee84 B9:34 BLEN:6 MTYPE:1c04 BODY:0f7dc4058344 CRC:f1
    
    public let blockType: MessageBlockType = .deactivatePod
    
    public var nonce: UInt32
    
    // e1f78752 07 8196
    public var data: Data {
        var data = Data([
            blockType.rawValue,
            4,
            ])
        data.appendBigEndian(nonce)
        return data
    }
    
    public init(encodedData: Data) throws {
        if encodedData.count < 6 {
            throw MessageBlockError.notEnoughData
        }
        self.nonce = encodedData[2...].toBigEndian(UInt32.self)
    }
    
    public init(nonce: UInt32) {
        self.nonce = nonce
    }
}
