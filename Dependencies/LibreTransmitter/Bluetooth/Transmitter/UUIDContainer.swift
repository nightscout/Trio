//
//  UUIDContainer.swift
//  MiaomiaoClient
//
//  Created by LoopKit Authors on 08/01/2020.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import CoreBluetooth
import Foundation
public struct UUIDContainer: ExpressibleByStringLiteral {
    public var value: CBUUID

    init(value: CBUUID) {
        self.value = value
    }
    public init(stringLiteral value: String) {
        self.value = CBUUID(string: value)
    }
}
