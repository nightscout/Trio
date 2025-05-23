// Trio
// SettingsProvider.swift
// Created by Ivan Valkou on 2021-02-02.

extension Settings {
    final class Provider: BaseProvider, SettingsProvider {
        @Injected() var tidepoolManager: TidepoolManager!
    }
}
