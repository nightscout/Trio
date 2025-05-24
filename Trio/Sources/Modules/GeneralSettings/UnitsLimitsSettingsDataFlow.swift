//
// Trio
// UnitsLimitsSettingsDataFlow.swift
// Created by Deniz Cengiz on 2025-01-01.
// Last edited by Deniz Cengiz on 2025-01-01.
// Most contributions by Deniz Cengiz.
//
// Documentation available under: https://triodocs.org/

import Combine

enum UnitsLimitsSettings {
    enum Config {}
}

protocol UnitsLimitsSettingsProvider: Provider {
    func settings() -> PumpSettings
    func save(settings: PumpSettings) -> AnyPublisher<Void, Error>
}
