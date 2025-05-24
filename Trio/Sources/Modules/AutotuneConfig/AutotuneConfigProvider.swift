//
// Trio
// AutotuneConfigProvider.swift
// Created by Deniz Cengiz on 2025-01-01.
// Last edited by Deniz Cengiz on 2025-01-01.
// Most contributions by Ivan Valkou.
//
// Documentation available under: https://triodocs.org/

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
