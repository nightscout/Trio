//
// Trio
// BGTargets.swift
// Created by Deniz Cengiz on 2025-01-01.
// Last edited by Marvin Polscheit on 2025-01-03.
// Most contributions by Ivan Valkou and Deniz Cengiz.
//
// Documentation available under: https://triodocs.org/

import Foundation

struct BGTargets: JSON {
    var units: GlucoseUnits
    var userPreferredUnits: GlucoseUnits
    var targets: [BGTargetEntry]
}

protocol BGTargetsObserver {
    func bgTargetsDidChange(_ bgTargets: BGTargets)
}

extension BGTargets {
    private enum CodingKeys: String, CodingKey {
        case units
        case userPreferredUnits = "user_preferred_units"
        case targets
    }
}

struct BGTargetEntry: JSON {
    let low: Decimal
    let high: Decimal
    let start: String
    let offset: Int
}
