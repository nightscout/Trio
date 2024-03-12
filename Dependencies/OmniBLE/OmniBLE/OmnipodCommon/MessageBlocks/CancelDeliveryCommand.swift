//
//  CancelDeliveryCommand.swift
//  OmniBLE
//
//  From OmniKit/MessageTransport/MessageBlocks/CancelDeliveryCommand.swift
//  Created by Pete Schwamb on 2/23/18.
//  Copyright © 2018 Pete Schwamb. All rights reserved.
//

import Foundation



public struct CancelDeliveryCommand : NonceResyncableMessageBlock {
    
    public let blockType: MessageBlockType = .cancelDelivery
    
    // ID1:1f00ee84 PTYPE:PDM SEQ:26 ID2:1f00ee84 B9:ac BLEN:7 MTYPE:1f05 BODY:e1f78752078196 CRC:03
    
    // Cancel bolus
    // 1f 05 be1b741a 64 - 1U
    // 1f 05 a00a1a95 64 - 1U over 1hr
    // 1f 05 ff52f6c8 64 - 1U immediate, 1U over 1hr
    
    // Cancel temp basal
    // 1f 05 f76d34c4 62 - 30U/hr
    // 1f 05 156b93e8 62 - ?
    // 1f 05 62723698 62 - 0%
    // 1f 05 2933db73 62 - 03ea
    
    // Suspend is a Cancel delivery, followed by a configure alerts command (0x19)
    // 1f 05 50f02312 03 191050f02312580f000f06046800001e0302
    
    // Deactivate pod:
    // 1f 05 e1f78752 07
    
    public struct DeliveryType: OptionSet, Equatable {
        public let rawValue: UInt8
        
        public static let none          = DeliveryType()
        public static let basal         = DeliveryType(rawValue: 1 << 0)
        public static let tempBasal     = DeliveryType(rawValue: 1 << 1)
        public static let bolus         = DeliveryType(rawValue: 1 << 2)
        
        public static let allButBasal: DeliveryType = [.tempBasal, .bolus]
        public static let all: DeliveryType = [.none, .basal, .tempBasal, .bolus]
        
        public init(rawValue: UInt8) {
            self.rawValue = rawValue
        }
        
    }
    
    public let deliveryType: DeliveryType
    
    public let beepType: BeepType
    
    public var nonce: UInt32
    
    public var data: Data {
        var data = Data([
            blockType.rawValue,
            5,
            ])
        data.appendBigEndian(nonce)
        data.append((beepType.rawValue << 4) + deliveryType.rawValue)
        return data
    }
    
    public init(encodedData: Data) throws {
        if encodedData.count < 7 {
            throw MessageBlockError.notEnoughData
        }
        self.nonce = encodedData[2...].toBigEndian(UInt32.self)
        self.deliveryType = DeliveryType(rawValue: encodedData[6] & 0xf)
        self.beepType = BeepType(rawValue: encodedData[6] >> 4)!
    }
    
    public init(nonce: UInt32, deliveryType: DeliveryType, beepType: BeepType) {
        self.nonce = nonce
        self.deliveryType = deliveryType
        self.beepType = beepType
    }
}

extension CancelDeliveryCommand: CustomDebugStringConvertible {
    public var debugDescription: String {
        return "CancelDeliveryCommand(nonce:\(Data(bigEndian: nonce).hexadecimalString), deliveryType:\(deliveryType), beepType:\(beepType))"
    }
}
