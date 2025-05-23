// Trio
// PumpStatus.swift
// Created by Ivan Valkou on 2021-03-07.

import Foundation

struct PumpStatus: JSON, Equatable {
    let status: StatusType
    let bolusing: Bool
    let suspended: Bool
    var timestamp: Date?
}

enum StatusType: String, JSON {
    case normal
    case suspended
    case bolusing
}
