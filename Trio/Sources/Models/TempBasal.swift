//
// Trio
// TempBasal.swift
// Created by Deniz Cengiz on 2025-01-01.
// Last edited by Deniz Cengiz on 2025-01-01.
// Most contributions by Ivan Valkou.
//
// Documentation available under: https://triodocs.org/

import Foundation

struct TempBasal: JSON {
    let duration: Int
    let rate: Decimal
    let temp: TempType
    let timestamp: Date
}
