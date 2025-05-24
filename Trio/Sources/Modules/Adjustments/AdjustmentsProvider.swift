//
// Trio
// AdjustmentsProvider.swift
// Created by Deniz Cengiz on 2025-01-01.
// Last edited by Marvin Polscheit on 2025-01-03.
// Most contributions by Deniz Cengiz.
//
// Documentation available under: https://triodocs.org/

extension Adjustments {
    final class Provider: BaseProvider, AdjustmentsProvider {
        func getBGTargets() async -> BGTargets {
            await storage.retrieveAsync(OpenAPS.Settings.bgTargets, as: BGTargets.self)
                ?? BGTargets(from: OpenAPS.defaults(for: OpenAPS.Settings.bgTargets))
                ?? BGTargets(units: .mgdL, userPreferredUnits: .mgdL, targets: [])
        }
    }
}
