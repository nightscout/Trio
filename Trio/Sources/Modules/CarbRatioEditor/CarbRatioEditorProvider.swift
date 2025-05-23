// Trio
// CarbRatioEditorProvider.swift
// Created by Ivan Valkou on 2021-03-03.

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
