// Trio
// PumpSettings.swift
// Created by Ivan Valkou on 2021-03-02.

import Foundation

struct PumpSettings: JSON {
    let insulinActionCurve: Decimal
    let maxBolus: Decimal
    let maxBasal: Decimal
}

extension PumpSettings {
    private enum CodingKeys: String, CodingKey {
        case insulinActionCurve = "insulin_action_curve"
        case maxBolus
        case maxBasal
    }
}
