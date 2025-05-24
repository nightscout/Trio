//
// Trio
// AutosensSettingsDataFlow.swift
// Created by Deniz Cengiz on 2025-01-01.
// Last edited by Deniz Cengiz on 2025-01-01.
// Most contributions by Deniz Cengiz and Andreas Stokholm.
//
// Documentation available under: https://triodocs.org/

enum AutosensSettings {
    enum Config {}
}

protocol AutosensSettingsProvider: Provider {
    var autosense: Autosens { get }
}
