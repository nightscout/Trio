//
// Trio
// NightscoutPreferences.swift
// Created by Deniz Cengiz on 2025-01-01.
// Last edited by Deniz Cengiz on 2025-01-01.
// Most contributions by Marc G. Fournier and Jon B Mårtensson.
//
// Documentation available under: https://triodocs.org/

import Foundation

struct NightscoutPreferences: JSON {
    var report = "preferences"
    let preferences: Preferences?
}
