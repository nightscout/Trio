// Trio
// UnitsLimitsSettingsDataFlow.swift
// Created by Deniz Cengiz on 2024-07-30.

import Combine

enum UnitsLimitsSettings {
    enum Config {}
}

protocol UnitsLimitsSettingsProvider: Provider {
    func settings() -> PumpSettings
    func save(settings: PumpSettings) -> AnyPublisher<Void, Error>
}
