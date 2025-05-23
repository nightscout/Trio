// Trio
// TreatmentsDataFlow.swift
// Created by Ivan Valkou on 2021-03-06.

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
