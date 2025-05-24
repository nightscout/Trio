//
// Trio
// CarbRatioEditorProvider.swift
// Created by Deniz Cengiz on 2025-01-01.
// Last edited by Marvin Polscheit on 2025-01-03.
// Most contributions by Ivan Valkou and Deniz Cengiz.
//
// Documentation available under: https://triodocs.org/

import Combine

extension CarbRatioEditor {
    final class Provider: BaseProvider, CarbRatioEditorProvider {
        var profile: CarbRatios {
            storage.retrieve(OpenAPS.Settings.carbRatios, as: CarbRatios.self)
                ?? CarbRatios(from: OpenAPS.defaults(for: OpenAPS.Settings.carbRatios))
                ?? CarbRatios(units: .grams, schedule: [])
        }

        func saveProfile(_ profile: CarbRatios) {
            storage.save(profile, as: OpenAPS.Settings.carbRatios)
        }
    }
}
