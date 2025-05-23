// Trio
// CGMSettingsProvider.swift
// Created by Deniz Cengiz on 2025-04-21.

extension CGMSettings {
    final class Provider: BaseProvider, CGMSettingsProvider {
        @Injected() var apsManager: APSManager!
    }
}
