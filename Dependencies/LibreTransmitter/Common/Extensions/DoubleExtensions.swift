//
//  DoubleExtensions.swift
//  MiaomiaoClientUI
//
//  Created by LoopKit Authors on 25/03/2019.
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import Foundation

extension Double {
    func roundTo(places: Int) -> Double {
        let divisor = pow(10.0, Double(places))
        return (self * divisor).rounded() / divisor
    }

    var twoDecimals: String {
        String(format: "%.2f", self)
    }
    
}
