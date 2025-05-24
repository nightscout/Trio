//
// Trio
// Battery.swift
// Created by Deniz Cengiz on 2025-01-01.
// Last edited by Deniz Cengiz on 2025-01-01.
// Most contributions by Ivan Valkou and Paul Plant.
//
// Documentation available under: https://triodocs.org/

import Foundation

struct Battery: JSON {
    let percent: Int?
    let voltage: Decimal?
    let string: BatteryState
    let display: Bool?
}

enum BatteryState: String, JSON {
    case normal
    case low
    case unknown
    case error
}
