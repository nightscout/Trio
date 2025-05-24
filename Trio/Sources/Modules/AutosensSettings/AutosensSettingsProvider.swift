//
// Trio
// AutosensSettingsProvider.swift
// Created by Deniz Cengiz on 2025-01-01.
// Last edited by Deniz Cengiz on 2025-01-01.
// Most contributions by Andreas Stokholm and Deniz Cengiz.
//
// Documentation available under: https://triodocs.org/

extension AutosensSettings {
    final class Provider: BaseProvider, AutosensSettingsProvider {
        var autosense: Autosens {
            storage.retrieve(OpenAPS.Settings.autosense, as: Autosens.self)
                ?? Autosens(from: OpenAPS.defaults(for: OpenAPS.Settings.autosense))
                ?? Autosens(ratio: 1, newisf: nil, timestamp: nil)
        }
    }
}
