// Trio
// Loops.swift
// Created by Jon B Mårtensson on 2023-08-26.

import Foundation

struct Loops: JSON, Equatable {
    var loops: Int
    var errors: Int
    var success_rate: Decimal
    var avg_interval: Decimal
    var median_interval: Decimal
    var min_interval: Decimal
    var max_interval: Decimal
    var avg_duration: Decimal
    var median_duration: Decimal
    var min_duration: Decimal
    var max_duration: Decimal
}
