// Trio
// NightscoutPreferences.swift
// Created by Jon B.M on 2023-03-05.

import Foundation

struct NightscoutPreferences: JSON {
    var report = "preferences"
    let preferences: Preferences?
}
