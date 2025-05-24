//
// Trio
// ISFEditorProvider.swift
// Created by Deniz Cengiz on 2025-01-01.
// Last edited by Marvin Polscheit on 2025-01-03.
// Most contributions by Deniz Cengiz and Ivan Valkou.
//
// Documentation available under: https://triodocs.org/

import Foundation

extension ISFEditor {
    final class Provider: BaseProvider, ISFEditorProvider {
        var profile: InsulinSensitivities {
            var retrievedSensitivities = storage.retrieve(OpenAPS.Settings.insulinSensitivities, as: InsulinSensitivities.self)
                ?? InsulinSensitivities(from: OpenAPS.defaults(for: OpenAPS.Settings.insulinSensitivities))
                ?? InsulinSensitivities(
                    units: .mgdL,
                    userPreferredUnits: .mgdL,
                    sensitivities: []
                )

            // migrate existing mmol/L Trio users from mmol/L settings to pure mg/dl settings
            if retrievedSensitivities.units == .mmolL || retrievedSensitivities.userPreferredUnits == .mmolL {
                let convertedSensitivities = retrievedSensitivities.sensitivities.map { isf in
                    InsulinSensitivityEntry(
                        sensitivity: storage.parseSettingIfMmolL(value: isf.sensitivity),
                        offset: isf.offset,
                        start: isf.start
                    )
                }
                retrievedSensitivities = InsulinSensitivities(
                    units: .mgdL,
                    userPreferredUnits: .mgdL,
                    sensitivities: convertedSensitivities
                )
                saveProfile(retrievedSensitivities)
            }

            return retrievedSensitivities
        }

        func saveProfile(_ profile: InsulinSensitivities) {
            storage.save(profile, as: OpenAPS.Settings.insulinSensitivities)
        }
    }
}
