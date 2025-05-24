//
// Trio
// TreatmentsDataFlow.swift
// Created by Deniz Cengiz on 2025-01-01.
// Last edited by Marvin Polscheit on 2025-01-03.
// Most contributions by Marvin Polscheit and Ivan Valkou.
//
// Documentation available under: https://triodocs.org/

enum Treatments {
    enum Config {}
}

protocol TreatmentsProvider: Provider {
    func getPumpSettings() async -> PumpSettings
    func getBasalProfile() async -> [BasalProfileEntry]
    func getCarbRatios() async -> CarbRatios
    func getBGTargets() async -> BGTargets
    func getISFValues() async -> InsulinSensitivities
}
