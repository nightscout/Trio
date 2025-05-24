//
// Trio
// CGMSettingsProvider.swift
// Created by Deniz Cengiz on 2025-02-17.
// Last edited by Deniz Cengiz on 2025-02-17.
// Most contributions by Deniz Cengiz.
//
// Documentation available under: https://triodocs.org/

extension CGMSettings {
    final class Provider: BaseProvider, CGMSettingsProvider {
        @Injected() var apsManager: APSManager!
    }
}
