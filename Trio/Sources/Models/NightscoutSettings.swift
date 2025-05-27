//
// Trio
// NightscoutSettings.swift
// Created by Deniz Cengiz on 2025-01-01.
// Last edited by Deniz Cengiz on 2025-01-01.
// Most contributions by Jon B Mårtensson and Deniz Cengiz.
//
// Documentation available under: https://triodocs.org/

import Foundation

struct NightscoutSettings: JSON {
    let report = "settings"
    let settings: TrioSettings?
}
