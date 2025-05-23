// Trio
// AutosensSettingsDataFlow.swift
// Created by Deniz Cengiz on 2025-04-21.

enum AutosensSettings {
    enum Config {}
}

protocol AutosensSettingsProvider: Provider {
    var autosense: Autosens { get }
}
