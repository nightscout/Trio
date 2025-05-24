//
// Trio
// SettingsProvider.swift
// Created by Deniz Cengiz on 2025-01-01.
// Last edited by Deniz Cengiz on 2025-01-01.
// Most contributions by Pierre L and Ivan Valkou.
//
// Documentation available under: https://triodocs.org/

extension Settings {
    final class Provider: BaseProvider, SettingsProvider {
        @Injected() var tidepoolManager: TidepoolManager!
    }
}
