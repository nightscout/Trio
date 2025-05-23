// Trio
// TempBasal.swift
// Created by Ivan Valkou on 2021-03-01.

import Foundation

struct TempBasal: JSON {
    let duration: Int
    let rate: Decimal
    let temp: TempType
    let timestamp: Date
}
