// Trio
// AutotuneConfigProvider.swift
// Created by Ivan Valkou on 2021-03-13.

import Combine

extension AutotuneConfig {
    final class Provider: BaseProvider, AutotuneConfigProvider {
        @Injected() private var apsManager: APSManager!

        var autotune: Autotune? {
            storage.retrieve(OpenAPS.Settings.autotune, as: Autotune.self)
        }

        func deleteAutotune() {
            storage.remove(OpenAPS.Settings.autotune)
        }
    }
}
