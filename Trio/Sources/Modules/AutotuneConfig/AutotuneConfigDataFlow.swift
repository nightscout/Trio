//
// Trio
// AutotuneConfigDataFlow.swift
// Created by Deniz Cengiz on 2025-01-01.
// Last edited by Deniz Cengiz on 2025-01-01.
// Most contributions by Ivan Valkou.
//
// Documentation available under: https://triodocs.org/

import Combine

enum AutotuneConfig {
    enum Config {}
}

protocol AutotuneConfigProvider: Provider {
    var autotune: Autotune? { get }
    func deleteAutotune()
}
