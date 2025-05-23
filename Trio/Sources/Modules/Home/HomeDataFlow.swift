// Trio
// HomeDataFlow.swift
// Created by Deniz Cengiz on 2025-04-21.

import Foundation
import LoopKitUI

enum Home {
    enum Config {}
}

protocol HomeProvider: Provider {
    func heartbeatNow()
    func pumpSettings() async -> PumpSettings
    func getBasalProfile() async -> [BasalProfileEntry]
    func pumpReservoir() async -> Decimal?
    func getBGTargets() async -> BGTargets
}
