// Trio
// Rounding.swift
// Created by Deniz Cengiz on 2024-08-12.

import Foundation

func rounded(_ value: Decimal, scale: Int, roundingMode: NSDecimalNumber.RoundingMode) -> Decimal {
    var result = Decimal()
    var toRound = value
    NSDecimalRound(&result, &toRound, scale, roundingMode)
    return result
}
