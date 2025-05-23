// Trio
// NightscoutSettings.swift
// Created by Jon B Mårtensson on 2023-12-11.

import Foundation

struct NightscoutSettings: JSON {
    let report = "settings"
    let settings: TrioSettings?
}
