//
//  DeactivatePodCommand.swift
//  OmniKit
//
//  Created by Pete Schwamb on 2/24/18.
//  Copyright © 2018 Pete Schwamb. All rights reserved.
//

import Foundation

public struct DeactivatePodCommand : NonceResyncableMessageBlock {
    // OFF 1  2 3 4 5
    // 1C 04 NNNNNNNN
    
    public let blockType: MessageBlockType = .deactivatePod
    
    public var nonce: UInt32
    
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
