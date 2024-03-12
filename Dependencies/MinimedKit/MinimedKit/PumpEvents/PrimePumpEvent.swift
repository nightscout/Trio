//
//  PrimePumpEvent.swift
//  RileyLink
//
//  Created by Pete Schwamb on 3/8/16.
//  Copyright © 2016 LoopKit Authors. All rights reserved.
//

import Foundation

public struct PrimePumpEvent: TimestampedPumpEvent {

    enum PrimeType: String {
        case manual
        case fixed
    }

    public let length: Int
    public let rawData: Data
    public let timestamp: DateComponents
    let amount: Double
    let primeType: PrimeType
    let programmedAmount: Double
    
    public init?(availableData: Data, pumpModel: PumpModel) {
        length = 10
        
        guard length <= availableData.count else {
            return nil
        }

        rawData = availableData.subdata(in: 0..<length)
        
        func d(_ idx: Int) -> Int {
            return Int(availableData[idx])
        }
        
        timestamp = DateComponents(pumpEventData: availableData, offset: 5)
        amount = Double(d(4) << 2) / 40.0
        programmedAmount = Double(d(2) << 2) / 40.0
        primeType = programmedAmount == 0 ? .manual : .fixed
    }
    
    public var dictionaryRepresentation: [String: Any] {
        return [
            "_type": "Prime",
            "amount": amount,
            "programmedAmount": programmedAmount,
            "primeType": primeType.rawValue,
        ]
    }
}
