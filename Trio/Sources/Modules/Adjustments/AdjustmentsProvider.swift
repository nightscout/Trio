// Trio
// AdjustmentsProvider.swift
// Created by Deniz Cengiz on 2025-04-21.

extension Adjustments {
    final class Provider: BaseProvider, AdjustmentsProvider {
        func getBGTargets() async -> BGTargets {
            await storage.retrieveAsync(OpenAPS.Settings.bgTargets, as: BGTargets.self)
                ?? BGTargets(from: OpenAPS.defaults(for: OpenAPS.Settings.bgTargets))
                ?? BGTargets(units: .mgdL, userPreferredUnits: .mgdL, targets: [])
        }
    }
}
