//
//  CBPeripheralExtensions.swift
//  MiaomiaoClient
//
//  Created by LoopKit Authors on 19/10/2020.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import CoreBluetooth
import Foundation

public protocol PeripheralProtocol {
    var name: String? { get }
    var name2: String { get }

    var asStringIdentifier: String { get }
}

public enum Either<A, B> {
  case Left(A)
  case Right(B)
}


extension CBPeripheral: PeripheralProtocol {
    public var name2: String {
        self.name ?? ""
    }

    public var asStringIdentifier: String {
        self.identifier.uuidString
    }
}
