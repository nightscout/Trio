//
// Trio
// HomeDataFlow.swift
// Created by Deniz Cengiz on 2025-01-01.
// Last edited by Deniz Cengiz on 2025-01-14.
// Most contributions by Ivan Valkou and Marvin Polscheit.
//
// Documentation available under: https://triodocs.org/

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
